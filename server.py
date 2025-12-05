import os
import secrets
import hashlib
import uuid
from datetime import datetime, timedelta, timezone
from functools import wraps
from flask import Flask, request, jsonify
from flask_cors import CORS
import firebase_admin
from firebase_admin import credentials, firestore
from firebase_admin.firestore import transactional
from dotenv import load_dotenv

load_dotenv()

API_SECRET = os.environ.get("OTP_API_SECRET")
FIREBASE_CRED = "firebase-service-account-key.json"
MISSED_CALL_NO = os.environ.get("MISSED_CALL_NO", "1234567890")

HOUR_OFFSET = 5
SLOT_COUNT = 19  
FULL_MASK = (1 << SLOT_COUNT) - 1  

if not firebase_admin._apps:
    cred = credentials.Certificate(FIREBASE_CRED)
    firebase_admin.initialize_app(cred)

db = firestore.client()
app = Flask(__name__)
CORS(app)

def require_secret(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        secret = request.headers.get("x-secret-key")
        if secret != API_SECRET:
            return jsonify({"error": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return wrapper

def now_ts():
    return firestore.SERVER_TIMESTAMP

def sanitize_phone(phone):
    if not phone:
        return None
    return "".join(c for c in phone if c.isdigit() or c == '+')

def gen_otp(length=6):
    return str(secrets.randbelow(10**length)).zfill(length)

def hash_code(code):
    return hashlib.sha256(code.encode()).hexdigest()

def hours_to_mask(start_hour, end_hour):
    """
    Converts [startHour, endHour) exclusive-end to a bitmask in our compressed 5..23 range.
    Example: start=7 end=10 will create bits for hours 7,8,9.
    Validates hours are inside [5..23] and start < end.
    """
    s = int(start_hour) - HOUR_OFFSET
    e = int(end_hour) - HOUR_OFFSET
    if s < 0 or e > SLOT_COUNT or s >= e:
        raise ValueError(f"Invalid hours range: {start_hour}-{end_hour}. Valid: {HOUR_OFFSET}..{HOUR_OFFSET+SLOT_COUNT-1}")
    length = e - s
    return ((1 << length) - 1) << s

def sim_sms_message(template, **kwargs):
    return template.format(**kwargs)

T_JOB_ALERT = ("[ROLE] JOB ALERT: Service requested at {locality} on {date}. "
               "Time: {from_time} to {to_time} (approx. {hours} hours) at ₹{wage}. "
               "Notes: {details}. To accept, reply 'ACCEPT' or use the app. Missed call: {missed_call_no} ~ Kaarya")
T_REMINDER = ("30 MINUTE REMINDER: Your [ROLE] job at {locality} starts at {from_time} on {date}. "
              "Full Address: {address}. For directions, click: {gmaps} ~ Team Kaarya")
T_START_OTP = ("JOB START OTP: Your code for the {locality} job on {date} ({from_time}-{to_time}) is {otp}. "
               "Total Est: ₹{wage} ({wph}/hr). Share with customer to confirm START.")
T_JOB_STARTED = ("JOB STARTED: {locality} job on {date} marked START at {actual_start}. You are now on the clock.")
T_END_OTP = ("JOB END OTP: Your completion code for the {locality} job on {date} is {otp}. "
             "Elapsed Time: {hours} hours (Final Wage: ₹{wage}). SHARE WITH CUSTOMER to confirm payment received.")

@app.route("/generate-otp", methods=["POST"])
def generate_otp():
    """
    Existing signup OTP generator (kept as-is).
    Expects header x-secret-key for internal testing.
    Body: { phone: "+911234..." }
    Stores under collection "otp" keyed by sanitized phone.
    """
    secret = request.headers.get("x-secret-key")
    if secret != API_SECRET:
        return jsonify({"error": "Unauthorized"}), 401

    phone = request.json.get("phone")
    if not phone:
        return jsonify({"error": "Phone required"}), 400

    sanitized_phone = sanitize_phone(phone)
    otp_code = gen_otp(6)
    correlation_id = str(uuid.uuid4())
    otp_hash = hash_code(otp_code)
    expires_at = int((datetime.now(timezone.utc) + timedelta(minutes=5)).timestamp())

    try:
        db.collection("otp").document(sanitized_phone).set({
            "hash": otp_hash,
            "correlation_id": correlation_id,
            "expires_at": expires_at,
            "sim_message": {
                "text": f"{otp_code} is your OTP verification code."
            }
        })
        print(f"[signup OTP] Generated OTP for {sanitized_phone}. CID {correlation_id}")
        return jsonify({"ok": True, "correlation_id": correlation_id}), 200
    except Exception as e:
        print("generate-otp error:", e)
        return jsonify({"error": str(e)}), 500

@app.route("/verify-otp-log", methods=["POST"])
def verify_otp_log():
    """
    Existing signup OTP verification (kept as-is).
    Body: { phone, code, correlation_id }
    On success writes to verified_signups and deletes the otp doc.
    """
    secret = request.headers.get("x-secret-key")
    if secret != API_SECRET:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.json or {}
    phone = data.get("phone")
    code = data.get("code")
    client_cid = data.get("correlation_id")

    sanitized_phone = sanitize_phone(phone)
    if not sanitized_phone or not code or not client_cid:
        return jsonify({"valid": False, "error": "Missing fields"}), 400

    doc_ref = db.collection("otp").document(sanitized_phone)
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"valid": False, "error": "OTP Expired"}), 400

    record = doc.to_dict()
    if record.get('hash') != hash_code(code):
        return jsonify({"valid": False, "error": "Invalid Code"}), 400
    if record.get('correlation_id') != client_cid:
        return jsonify({"valid": False, "error": "Session Mismatch"}), 400
    if int(datetime.now(timezone.utc).timestamp()) > int(record.get('expires_at', 0)):
        return jsonify({"valid": False, "error": "Expired"}), 400

    try:
        db.collection("verified_signups").document(sanitized_phone).set({
            "phone": sanitized_phone,
            "correlation_id": client_cid,
            "verified_at": firestore.SERVER_TIMESTAMP,
            "status": "verified_pending_signup"
        })
        doc_ref.delete()
        return jsonify({"valid": True, "message": "Verified"}), 200
    except Exception as e:
        print("verify-otp-log error:", e)
        return jsonify({"error": "Logging failed"}), 500

@app.route("/create-booking", methods=["POST"])
@require_secret
def create_booking():
    """
    Create a booking and create workerRequests subdocs for candidate workers (Book Any dispatch).
    Body:
      {
        userId, userPhone,
        candidateWorkers: [workerId...],
        date: "YYYY-MM-DD", startHour: int, endHour: int,
        wage: int, ta: int (optional), serviceType, location: {...}, notes
      }
    """
    data = request.json or {}
    required = ["userId", "date", "startHour", "endHour", "wage", "candidateWorkers"]
    for r in required:
        if r not in data:
            return jsonify({"error": f"{r} required"}), 400

    userId = data["userId"]
    userPhone = sanitize_phone(data.get("userPhone"))
    candidate_workers = data.get("candidateWorkers", [])
    date_id = data["date"]
    startHour = int(data["startHour"])
    endHour = int(data["endHour"])
    wage = int(data["wage"])
    ta = int(data.get("ta", 0))
    serviceType = data.get("serviceType")
    location = data.get("location", {})
    notes = data.get("notes", "")

    try:
        needed_mask = hours_to_mask(startHour, endHour)
    except Exception as e:
        return jsonify({"error": str(e)}), 400

    booking_ref = db.collection("bookings").document()
    booking_id = booking_ref.id
    now = firestore.SERVER_TIMESTAMP

    booking_obj = {
        "userId": userId,
        "userPhone": userPhone,
        "assignedWorker": None,
        "workerId": None,
        "status": "b1",  
        "date": date_id,
        "startHour": startHour,
        "endHour": endHour,
        "serviceType": serviceType,
        "createdAt": now,
        "bookingDate": now,
        "updatedAt": now,
        "wage": wage,
        "ta": ta,
        "notes": notes,
        "location": location,
        "payment": {
            "method": data.get("paymentMethod", "cash"),
            "status": "pending",
            "digitalTxId": None,
            "cashReceivedConfirmedByWorkerAt": None
        },
        "log": {
            "createdAt": now,
            "createdBy": userId,
            "actions": []
        }
    }

    try:
        batch = db.batch()
        batch.set(booking_ref, booking_obj)

        sent_at = now
        for wid in candidate_workers:
            wr_ref = booking_ref.collection("workerRequests").document(wid)
            wr_obj = {
                "workerId": wid,
                "status": "pending",  
                "sentAt": sent_at,
                "acceptedAt": None,
                "updatedAt": sent_at,

                "sim_message": {
                    "text": sim_sms_message(T_JOB_ALERT,
                                           locality=location.get("locality", location.get("address", "Unknown")),
                                           date=date_id,
                                           from_time=f"{startHour}:00",
                                           to_time=f"{endHour}:00",
                                           hours=(endHour - startHour),
                                           wage=wage,
                                           details=notes,
                                           missed_call_no=MISSED_CALL_NO)
                }
            }
            batch.set(wr_ref, wr_obj)

        batch.update(booking_ref, {"status": "b2", "candidateWorkers": candidate_workers, "updatedAt": now})
        batch.commit()
        return jsonify({"ok": True, "bookingId": booking_id}), 200
    except Exception as e:
        print("create-booking error:", e)
        return jsonify({"error": str(e)}), 500

@transactional
def submit_rating_in_transaction(tx, booking_ref, worker_ref, userId, rating, review):
    """
    Atomically updates booking and recalculates worker's average rating.
    """

    booking_snap = booking_ref.get(transaction=tx)
    if not booking_snap.exists:
        raise Exception("Booking not found")

    booking_data = booking_snap.to_dict()

    worker_snap = worker_ref.get(transaction=tx)
    if not worker_snap.exists:
        raise Exception("Worker not found")

    worker_data = worker_snap.to_dict()

    if booking_data.get("userId") != userId:
        raise Exception("User mismatch. Not authorized to rate this booking.")

    if booking_data.get("rating", 0) > 0:
        raise Exception("This booking has already been rated.")

    old_avg = float(worker_data.get("avgRating", 0.0))

    job_count = int(worker_data.get("completedBookings", 0))

    if job_count == 0:

        new_avg = rating
    else:

        new_avg = ((old_avg * (job_count - 1)) + rating) / job_count

    tx.update(booking_ref, {
        "rating": rating,
        "review": review,
        "updatedAt": now_ts()
    })

    tx.update(worker_ref, {
        "avgRating": new_avg,
        "updatedAt": now_ts()
    })

    return True

@app.route("/submit-rating", methods=["POST"])
@require_secret
def submit_rating():
    """
    Body: { userId, bookingId, workerId, rating, review (optional) }
    """
    data = request.json or {}
    userId = data.get("userId")
    bookingId = data.get("bookingId")
    workerId = data.get("workerId")
    rating = float(data.get("rating", 0.0))
    review = data.get("review", f"Rated {rating} stars")

    if not userId or not bookingId or not workerId or rating <= 0:
        return jsonify({"error": "userId, bookingId, workerId, and rating are required"}), 400

    try:
        booking_ref = db.collection("bookings").document(bookingId)
        worker_ref = db.collection("workers").document(workerId)

        transaction = db.transaction()
        submit_rating_in_transaction(transaction, booking_ref, worker_ref, userId, rating, review)

        return jsonify({"ok": True, "message": "Rating submitted successfully"}), 200

    except Exception as e:
        print("submit-rating error:", e)
        return jsonify({"ok": False, "error": str(e)}), 400

@transactional
def accept_booking_in_transaction(tx, booking_ref, req_ref, workerId):
    """
    This function will be run inside a transaction.
    All reads MUST happen before all writes.
    """

    b_snap = booking_ref.get(transaction=tx)
    if not b_snap.exists:
        raise Exception("BOOKING_NOT_FOUND")
    booking = b_snap.to_dict()

    req_snap = req_ref.get(transaction=tx)
    if not req_snap.exists:
        raise Exception("NOT_INVITED")

    avail_ref = db.collection("workers").document(workerId).collection("availability").document(booking["date"])
    avail_snap = avail_ref.get(transaction=tx)

    all_reqs_stream = booking_ref.collection("workerRequests").stream(transaction=tx)

    all_reqs_list = [req for req in all_reqs_stream]

    if booking.get("assignedWorker"):
        raise Exception("ALREADY_ASSIGNED")
    if booking.get("status") not in ("b1", "b2"):
        raise Exception("BOOKING_NOT_PENDING")

    current_mask = FULL_MASK
    if avail_snap.exists:
        current_mask = int(avail_snap.to_dict().get("mask", FULL_MASK))

    needed_mask = hours_to_mask(booking["startHour"], booking["endHour"])

    if (current_mask & needed_mask) != needed_mask:

        tx.update(req_ref, {"status": "rejected", "updatedAt": now_ts()})
        raise Exception("WORKER_NOT_AVAILABLE")

    tx.update(booking_ref, {
        "assignedWorker": workerId,
        "workerId": workerId,
        "status": "a1",  
        "assignedAt": now_ts(),
        "updatedAt": now_ts()
    })

    tx.update(req_ref, {"status": "accepted", "acceptedAt": now_ts(), "updatedAt": now_ts()})

    for orq in all_reqs_list:
        if orq.id != workerId:
            tx.update(orq.reference, {"status": "expired", "updatedAt": now_ts()})

    new_mask = current_mask & (~needed_mask)
    tx.set(avail_ref, {"mask": new_mask, "updatedAt": now_ts()}, merge=True)

    log_time = datetime.now(timezone.utc)
    tx.update(booking_ref, {"log.actions": firestore.ArrayUnion([{
        "ts": log_time,
        "actor": workerId,
        "action": "accepted",
        "info": {"startHour": booking["startHour"], "endHour": booking["endHour"]}
    }])})

    return True

@app.route("/worker-accept", methods=["POST"])
@require_secret
def worker_accept():
    """
    Body: { workerId, bookingId }
    Atomically assigns booking to first acceptor.
    """
    data = request.json or {}
    workerId = data.get("workerId")
    bookingId = data.get("bookingId")
    if not workerId or not bookingId:
        return jsonify({"error": "workerId and bookingId required"}), 400

    try:
        booking_ref = db.collection("bookings").document(bookingId)
        req_ref = booking_ref.collection("workerRequests").document(workerId)

        transaction = db.transaction()
        accept_booking_in_transaction(transaction, booking_ref, req_ref, workerId)

        return jsonify({"ok": True, "msg": "assigned"}), 200

    except Exception as e:
        print("worker-accept error:", e)

        return jsonify({"ok": False, "error": str(e)}), 400

@app.route("/worker-reject", methods=["POST"])
@require_secret
def worker_reject():
    data = request.json or {}
    workerId = data.get("workerId")
    bookingId = data.get("bookingId")
    if not workerId or not bookingId:
        return jsonify({"error": "workerId and bookingId required"}), 400
    req_ref = db.collection("bookings").document(bookingId).collection("workerRequests").document(workerId)
    try:
        req_ref.update({"status": "rejected", "updatedAt": now_ts()})
        return jsonify({"ok": True}), 200
    except Exception as e:
        print("worker-reject error:", e)
        return jsonify({"error": str(e)}), 500

@app.route("/generate-start-otp", methods=["POST"])
@require_secret
def generate_start_otp():
    """
    Body: { bookingId, userId }
    Fetches worker's phone.
    Creates an OTP event under bookings/{bid}/otpEvents/{cid} (without sim_message).
    Creates/overwrites an OTP doc under otp/{worker_phone} (with sim_message), mirroring signup.
    Updates booking.status to w1 and logs event.
    """
    data = request.json or {}
    bookingId = data.get("bookingId")
    userId = data.get("userId")
    if not bookingId or not userId:
        return jsonify({"error": "bookingId and userId required"}), 400

    booking_ref = db.collection("bookings").document(bookingId)
    b = booking_ref.get()
    if not b.exists:
        return jsonify({"error": "BOOKING_NOT_FOUND"}), 404
    booking = b.to_dict()

    if booking.get("userId") != userId:
        return jsonify({"error": "NOT_ASSIGNED_USER"}), 403

    workerId = booking.get("workerId")
    if not workerId:
        return jsonify({"error": "BOOKING_NOT_ASSIGNED"}), 400 

    worker_ref = db.collection("workers").document(workerId)
    w_snap = worker_ref.get()
    if not w_snap.exists:
        return jsonify({"error": "WORKER_NOT_FOUND"}), 404

    worker_phone = w_snap.to_dict().get("phone")
    if not worker_phone:
        return jsonify({"error": "WORKER_HAS_NO_PHONE"}), 400

    sanitized_phone = sanitize_phone(worker_phone)
    if not sanitized_phone:
         return jsonify({"error": "WORKER_PHONE_INVALID"}), 400

    otp_plain = gen_otp(6)
    cid = str(uuid.uuid4())
    otp_hashed = hash_code(otp_plain)
    expires_at = int((datetime.now(timezone.utc) + timedelta(minutes=10)).timestamp())
    now_for_fields = now_ts()
    now_for_logs = datetime.now(timezone.utc)

    start_hour = int(booking.get("startHour", 0))
    end_hour = int(booking.get("endHour", 0))
    duration = max(1, end_hour - start_hour)
    wage = int(booking.get("wage", 0))
    wph = wage // duration

    sim_msg_text = sim_sms_message(T_START_OTP,
        locality=booking.get("location", {}).get("locality", booking.get("location", {}).get("address", "Unknown")),
        date=booking["date"],
        from_time=f"{start_hour}:00",
        to_time=f"{end_hour}:00",
        otp=otp_plain,
        wage=wage,
        wph=wph
    )

    otp_event_doc = {
        "type": "start",
        "otpHash": otp_hashed,
        "otpPlainSim": otp_plain, 
        "generatedAt": now_for_fields,
        "expiresAt": expires_at,
        "verified": False,
        "verifiedAt": None,
        "verifiedBy": None,
        "statusCode": "w1",
        "correlationId": cid,

    }

    otp_super_doc = {
        "hash": otp_hashed,
        "correlation_id": cid, 
        "expires_at": expires_at,
        "sim_message": {
            "text": sim_msg_text
        }
    }

    try:
        otp_event_ref = booking_ref.collection("otpEvents").document(cid)
        otp_super_ref = db.collection("otp").document(sanitized_phone)

        batch = db.batch()

        batch.create(otp_event_ref, otp_event_doc)

        batch.set(otp_super_ref, otp_super_doc) 

        batch.update(booking_ref, {
            "status": "w1",
            "startOTPCorrelationId": cid,
            "startOTPSentAt": now_for_fields,
            "updatedAt": now_for_fields,
            "log.actions": firestore.ArrayUnion([{
                "ts": now_for_logs,
                "actor": userId,
                "action": "start_otp_generated",
                "info": {"correlationId": cid, "recipient": sanitized_phone}
            }])
        })
        batch.commit()
        return jsonify({"ok": True, "correlationId": cid}), 200
    except Exception as e:
        print("generate-start-otp error:", e)
        return jsonify({"error": str(e)}), 500

@app.route("/verify-start-otp", methods=["POST"])
@require_secret
def verify_start_otp():
    """
    Body: { bookingId, correlationId, code, verifiedBy: 'user'|'worker' }
    """
    data = request.json or {}
    bookingId = data.get("bookingId")
    cid = data.get("correlationId")
    code = data.get("code")
    verifiedBy = data.get("verifiedBy", "user")
    if not bookingId or not cid or not code:
        return jsonify({"error": "bookingId, correlationId, code required"}), 400

    booking_ref = db.collection("bookings").document(bookingId)
    otp_ref = booking_ref.collection("otpEvents").document(cid)
    otp_snap = otp_ref.get()
    if not otp_snap.exists:
        return jsonify({"error": "OTP_NOT_FOUND"}), 404
    otp_doc = otp_snap.to_dict()

    if int(datetime.now(timezone.utc).timestamp()) > int(otp_doc.get("expiresAt", 0)):
        return jsonify({"valid": False, "error": "EXPIRED"}), 400
    if hash_code(code) != otp_doc.get("otpHash"):
        return jsonify({"valid": False, "error": "INVALID"}), 400

    try:

        now_for_fields = now_ts() 
        now_for_logs = datetime.now(timezone.utc) 

        batch = db.batch()
        batch.update(otp_ref, {"verified": True, "verifiedAt": now_for_fields, "verifiedBy": verifiedBy, "updatedAt": now_for_fields})
        batch.update(booking_ref, {
            "status": "w2",
            "startConfirmedAt": now_for_fields,
            "workStartedAt": now_for_fields,
            "updatedAt": now_for_fields,
            "log.actions": firestore.ArrayUnion([{
                "ts": now_for_logs, 
                "actor": verifiedBy,
                "action": "start_otp_verified",
                "info": {"correlationId": cid}
            }])
        })
        batch.commit()
        return jsonify({"valid": True}), 200
    except Exception as e:
        print("verify-start-otp error:", e)
        return jsonify({"error": str(e)}), 500

@app.route("/generate-end-otp", methods=["POST"])
@require_secret
def generate_end_otp():
    """
    Body: { bookingId, requestedBy: 'user'|'worker' }
    Fetches worker's phone.
    Creates an OTP event under bookings/{bid}/otpEvents/{cid} (without sim_message).
    Creates/overwrites an OTP doc under otp/{worker_phone} (with sim_message), mirroring signup.
    Updates booking.status and logs event.
    """
    data = request.json or {}
    bookingId = data.get("bookingId")
    requestedBy = data.get("requestedBy", "worker")
    if not bookingId:
        return jsonify({"error": "bookingId required"}), 400

    booking_ref = db.collection("bookings").document(bookingId)
    b = booking_ref.get()
    if not b.exists:
        return jsonify({"error": "BOOKING_NOT_FOUND"}), 404
    booking = b.to_dict()

    workerId = booking.get("workerId")
    if not workerId:
        return jsonify({"error": "BOOKING_NOT_ASSIGNED"}), 400

    worker_ref = db.collection("workers").document(workerId)
    w_snap = worker_ref.get()
    if not w_snap.exists:
        return jsonify({"error": "WORKER_NOT_FOUND"}), 404

    worker_phone = w_snap.to_dict().get("phone")
    if not worker_phone:
        return jsonify({"error": "WORKER_HAS_NO_PHONE"}), 400

    sanitized_phone = sanitize_phone(worker_phone)
    if not sanitized_phone:
         return jsonify({"error": "WORKER_PHONE_INVALID"}), 400

    otp_plain = gen_otp(6)
    cid = str(uuid.uuid4())
    otp_hashed = hash_code(otp_plain)
    expires_at = int((datetime.now(timezone.utc) + timedelta(minutes=10)).timestamp())
    now_for_fields = now_ts()
    now_for_logs = datetime.now(timezone.utc)

    start_hour = int(booking.get("startHour", 0))
    end_hour = int(booking.get("endHour", start_hour))
    duration = max(0, end_hour - start_hour)
    wage = int(booking.get("wage", 0))

    status_code = "e1" if requestedBy == "user" else "e2"

    sim_msg_text = sim_sms_message(T_END_OTP,
        locality=booking.get("location", {}).get("locality", booking.get("location", {}).get("address", "Unknown")),
        date=booking["date"],
        otp=otp_plain,
        hours=duration,
        wage=wage
    )

    otp_event_doc = {
        "type": "end",
        "otpHash": otp_hashed,
        "otpPlainSim": otp_plain, 
        "generatedAt": now_for_fields,
        "expiresAt": expires_at,
        "verified": False,
        "verifiedAt": None,
        "verifiedBy": None,
        "statusCode": status_code,
        "correlationId": cid,

    }

    otp_super_doc = {
        "hash": otp_hashed,
        "correlation_id": cid, 
        "expires_at": expires_at,
        "sim_message": {
            "text": sim_msg_text
        }
    }

    try:
        otp_event_ref = booking_ref.collection("otpEvents").document(cid)
        otp_super_ref = db.collection("otp").document(sanitized_phone) 

        batch = db.batch()

        batch.create(otp_event_ref, otp_event_doc)

        batch.set(otp_super_ref, otp_super_doc) 

        batch.update(booking_ref, {
            "status": status_code,
            "endOTPCorrelationId": cid,
            "endOTPSentAt": now_for_fields,
            "updatedAt": now_for_fields,
            "log.actions": firestore.ArrayUnion([{
                "ts": now_for_logs,
                "actor": requestedBy,
                "action": "end_otp_generated",
                "info": {"correlationId": cid, "recipient": sanitized_phone}
            }])
        })
        batch.commit()

        return jsonify({"ok": True, "correlationId": cid, "sim_message": otp_super_doc["sim_message"]}), 200
    except Exception as e:
        print("generate-end-otp error:", e)
        return jsonify({"error": str(e)}), 500

@app.route("/verify-end-otp", methods=["POST"])
@require_secret
def verify_end_otp():
    """
    Body: { bookingId, correlationId, code, verifiedBy: 'user'|'worker', paymentReceived: bool (optional) }
    """
    data = request.json or {}
    bookingId = data.get("bookingId")
    cid = data.get("correlationId")
    code = data.get("code")
    verifiedBy = data.get("verifiedBy", "user")
    paymentReceived = data.get("paymentReceived", False)
    digitalTxId = data.get("digitalTxId", None)

    if not bookingId or not cid or not code:
        return jsonify({"error": "bookingId, correlationId, code required"}), 400

    booking_ref = db.collection("bookings").document(bookingId)
    otp_ref = booking_ref.collection("otpEvents").document(cid)

    booking_doc = booking_ref.get()
    if not booking_doc.exists:
        return jsonify({"error": "BOOKING_NOT_FOUND"}), 404

    booking_data = booking_doc.to_dict()
    payment_method = (booking_data.get("payment", {}) or {}).get("method", "cash")

    workerId = booking_data.get("workerId")
    worker_ref = db.collection("workers").document(workerId) if workerId else None

    otp_snap = otp_ref.get()
    if not otp_snap.exists:
        return jsonify({"error": "OTP_NOT_FOUND"}), 404
    otp_doc = otp_snap.to_dict()

    if int(datetime.now(timezone.utc).timestamp()) > int(otp_doc.get("expiresAt", 0)):
        return jsonify({"valid": False, "error": "EXPIRED"}), 400
    if hash_code(code) != otp_doc.get("otpHash"):
        return jsonify({"valid": False, "error": "INVALID"}), 400

    try:
        now_for_fields = now_ts()
        now_for_logs = datetime.now(timezone.utc)

        payment_obj = {
            "method": payment_method,
            "status": "paid" if paymentReceived else "pending",
            "digitalTxId": digitalTxId,
            "cashReceivedConfirmedByWorkerAt": now_for_fields if paymentReceived else None
        }

        batch = db.batch()
        batch.update(otp_ref, {"verified": True, "verifiedAt": now_for_fields, "verifiedBy": verifiedBy, "updatedAt": now_for_fields})
        batch.update(booking_ref, {
            "status": "e3",
            "endConfirmedAt": now_for_fields,
            "completedAt": now_for_fields,
            "payment": payment_obj,
            "updatedAt": now_for_fields,
            "log.actions": firestore.ArrayUnion([{
                "ts": now_for_logs,
                "actor": verifiedBy,
                "action": "end_otp_verified",
                "info": {"correlationId": cid, "paymentReceived": paymentReceived}
            }])
        })

        if worker_ref:
            batch.update(worker_ref, {
                "completedBookings": firestore.Increment(1)
            })

        batch.commit()
        return jsonify({"valid": True}), 200
    except Exception as e:
        print("verify-end-otp error:", e)
        return jsonify({"error": str(e)}), 500

@app.route("/get-booking/<bookingId>", methods=["GET"])
@require_secret
def get_booking(bookingId):
    try:
        b = db.collection("bookings").document(bookingId).get()
        if not b.exists:
            return jsonify({"error": "not found"}), 404
        doc = b.to_dict()
        reqs = [r.to_dict() for r in b.reference.collection("workerRequests").stream()]
        otps = [o.to_dict() for o in b.reference.collection("otpEvents").stream()]
        doc["workerRequests"] = reqs
        doc["otpEvents"] = otps
        return jsonify({"ok": True, "booking": doc}), 200
    except Exception as e:
        print("get-booking error:", e)
        return jsonify({"error": str(e)}), 500

@app.route("/expire-requests", methods=["POST"])
@require_secret
def expire_requests():
    """
    Will expire pending workerRequests older than threshold (seconds).
    Body optional: { olderThanSeconds: 120 }
    Note: for production, implement better TTL-based expiry or cloud scheduler queries.
    """
    data = request.json or {}
    older = int(data.get("olderThanSeconds", 120))
    cutoff_ts = datetime.now(timezone.utc).timestamp() - older
    try:
        q = db.collection("bookings").where("status", "==", "b2").stream()
        updated = 0
        for b in q:
            br = b.reference
            for req in br.collection("workerRequests").where("status", "==", "pending").stream():

                req.reference.update({"status": "expired", "updatedAt": now_ts()})
                updated += 1

        return jsonify({"ok": True, "expiredRequests": updated}), 200
    except Exception as e:
        print("expire-requests error:", e)
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":

    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=True)
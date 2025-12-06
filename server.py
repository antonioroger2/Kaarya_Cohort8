import os
import secrets
import hashlib
import uuid
import json
import requests
import re
from datetime import datetime, timedelta, timezone
from functools import wraps
from flask import Flask, request, jsonify
from flask_cors import CORS
import firebase_admin
from firebase_admin import credentials, firestore, auth
from firebase_admin.firestore import transactional
from dotenv import load_dotenv

load_dotenv()

# --- CONFIGURATION ---
API_SECRET = os.environ.get("OTP_API_SECRET", "")
FIREBASE_CRED = "firebase-service-account-key.json"
MISSED_CALL_NO = os.environ.get("MISSED_CALL_NO", "1234567890")
EMAIL_SUFFIX = "@kaaryaconnect.app"

# AI & Vector Config
HF_API_KEY = os.environ.get("HF_API_KEY", "")
PINECONE_API_KEY = os.environ.get("PINECONE_API_KEY", "")
PINECONE_HOST = os.environ.get("PINECONE_HOST", "https://llama-text-embed-v2-index-0s8x0bx.svc.aped-4627-b74a.pinecone.io")

# Business Logic Constants
HOUR_OFFSET = 0
SLOT_COUNT = 24
FULL_MASK = (1 << SLOT_COUNT) - 1

# Headers for External APIs
headers_llm = {"Authorization": f"Bearer {HF_API_KEY}", "Content-Type": "application/json"}
headers_pinecone = {"Api-Key": PINECONE_API_KEY, "Content-Type": "application/json"}
HF_LLM_URL = "https://router.huggingface.co/v1/chat/completions"

# --- INIT FIREBASE ---
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate(FIREBASE_CRED)
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"FIREBASE INIT ERROR: {e}")

db = firestore.client()
app = Flask(__name__)
CORS(app)

# --- DB COLLECTION NAMES ---
COL_USERS = "users"
COL_WORKERS = "workers"
COL_BOOKINGS = "bookings"
COL_CW = "canonical_works"
COL_TOOLS = "tools" # New collection
COL_OTP = "otp"
COL_VERIFIED = "verified_signups"
COL_HISTORY = "raw_to_canonical_history" # New collection

# --- SMS TEMPLATES ---
T_JOB_ALERT = ("[{role}] JOB ALERT: Service requested at {locality} on {date}. "
               "Time: {from_time} to {to_time} (approx. {hours} hours) at ₹{wage}. "
               "Notes: {details}. To accept, reply 'ACCEPT' or use the app. Missed call: {missed_call_no} ~ Kaarya")
T_REMINDER = ("30 MINUTE REMINDER: Your [{role}] job at {locality} starts at {from_time} on {date}. "
              "Full Address: {address}. For directions, click: {gmaps} ~ Team Kaarya")
T_START_OTP = ("JOB START OTP: Your code for the {locality} job on {date} ({from_time}-{to_time}) is {otp}. "
               "Total Est: ₹{wage} ({wph}/hr). Share with customer to confirm START.")
T_END_OTP = ("JOB END OTP: Your completion code for the {locality} job on {date} is {otp}. "
             "Elapsed Time: {hours} hours (Final Wage: ₹{wage}). SHARE WITH CUSTOMER to confirm payment received.")

# --- HELPER FUNCTIONS: CORE ---

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
    if not phone: return None
    return "".join(c for c in phone if c.isdigit() or c == '+')

def gen_otp(length=6):
    return str(secrets.randbelow(10**length)).zfill(length)

def hash_code(code):
    return hashlib.sha256(code.encode()).hexdigest()

def hours_to_mask(start_hour, end_hour):
    s = int(start_hour) - HOUR_OFFSET
    e = int(end_hour) - HOUR_OFFSET
    if e == SLOT_COUNT: e = 24
    if s < 0 or e > SLOT_COUNT or s > e:
        raise ValueError(f"Invalid hours range: {start_hour}-{end_hour}. Valid: 0..24")
    length = e - s
    if length <= 0: return 0
    return ((1 << length) - 1) << s

def sim_sms_message(template, **kwargs):
    return template.format(**kwargs)

def slugify(text):
    # Modified slugify to allow underscores for readability in Firestore keys
    text = text.lower()
    text = re.sub(r'[^a-z0-9\s]+', '', text) # Remove punctuation except spaces
    text = re.sub(r'\s+', '_', text) # Replace spaces with underscore
    return text.strip('_')

# --- HELPER FUNCTIONS: AI & VECTOR ---

def run_llm(prompt, max_new_tokens=200):
    """Unified LLM interface using HuggingFace API"""
    if not HF_API_KEY: return "LLM_DISABLED"
    payload = {
        "model": "mistralai/Mistral-7B-Instruct-v0.2:featherless-ai",
        "messages": [{"role": "user", "content": prompt}],
        "stream": False, "max_tokens": max_new_tokens, "temperature": 0.3
    }
    try:
        r = requests.post(HF_LLM_URL, headers=headers_llm, json=payload)
        if r.status_code != 200:
            print(f"LLM API Error: {r.status_code} {r.text}")
            return "LLM_ERROR"
        return r.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"LLM Error: {e}")
        return "LLM_ERROR"

def pinecone_embed_text(text):
    """Use Pinecone's built-in embedding model (llama-text-embed-v2)"""
    if not PINECONE_API_KEY: return [0.0] * 1024

    url = f"{PINECONE_HOST}/embed"
    payload = {
        "model": "llama-text-embed-v2",
        "inputs": [{"text": text}]
    }

    try:
        r = requests.post(url, headers=headers_pinecone, json=payload)
        if r.status_code != 200:
            print(f"Pinecone embed error: {r.status_code} {r.text}")
            return [0.0] * 1024

        data = r.json()
        embeddings = data.get("data", [])
        if embeddings and len(embeddings) > 0:
            return embeddings[0].get("values", [0.0] * 1024)
        return [0.0] * 1024
    except Exception as e:
        print(f"Pinecone embed exception: {e}")
        return [0.0] * 1024

def pinecone_upsert(vector_id, embedding, metadata):
    """Upsert vector to Pinecone"""
    if not PINECONE_API_KEY: return True
    url = f"{PINECONE_HOST}/vectors/upsert"
    payload = {
        "vectors": [{
            "id": vector_id,
            "values": embedding,
            "metadata": metadata
        }]
    }
    try:
        r = requests.post(url, headers=headers_pinecone, json=payload)
        return r.status_code < 400
    except:
        return False

def pinecone_query(embedding, top_k=5, filter_dict=None):
    """Query Pinecone for similar vectors"""
    if not PINECONE_API_KEY: return []

    url = f"{PINECONE_HOST}/query"
    payload = {
        "vector": embedding,
        "topK": top_k,
        "includeMetadata": True
    }
    if filter_dict:
        payload["filter"] = filter_dict

    try:
        r = requests.post(url, headers=headers_pinecone, json=payload)
        if r.status_code >= 400: return []
        matches = r.json().get("matches", [])
        return [{
            "id": m.get("id"),
            "score": m.get("score", 0.0),
            "metadata": m.get("metadata", {})
        } for m in matches]
    except:
        return []

def extract_entities(text):
    """Extract job-relevant entities from text"""
    t = text.lower()
    devices = ["tap", "pipe", "flush", "tank", "faucet", "shower", "toilet", "fan",
                "geyser", "ac", "switchboard", "curtain rod", "door", "window", "light",
                "furniture", "table", "chair", "sofa", "shelf"]
    issues = ["leak", "leaking", "broken", "jammed", "loose", "blocked", "crack",
              "not working", "no power", "noise", "install", "repair", "fix",
              "assembly", "polish", "paint", "cleaning"]
    rooms = ["kitchen", "bathroom", "hall", "bedroom", "living room", "office"]

    return {
        "devices": [d for d in devices if d in t],
        "issues": [i for i in issues if i in t],
        "rooms": [r for r in rooms if r in t]
    }

def llm_generate_canonical_work(user_input, entities=None):
    """Generate a standardized canonical work name"""
    entities_str = f"Entities: {entities}" if entities and any(entities.values()) else ""
    prompt = f"""User description: "{user_input}"
{entities_str}

Create a clean, short, standardized job name (3 words max) that can be used for search/categorization.
Examples: "Tap Fix", "Pipe Leak Repair", "Fan Installation", "AC Servicing", "Furniture Assembly"

Return ONLY the job name, nothing else."""

    result = run_llm(prompt, max_new_tokens=32)
    if "\n" in result:
        result = result.split("\n")[0].strip()
    return result

def llm_suggest_tools(canonical_work, description=""):
    """Suggest required tools for a canonical work"""
    prompt = f"""Job: "{canonical_work}"
Description: "{description}"

List the essential tools needed for this job (max 5). Format: one tool per line.
Examples:
- Wrench Set
- Screwdriver Kit
- Power Drill
- Pipe Cutter
- Teflon Tape

List tools:"""

    result = run_llm(prompt, max_new_tokens=100)
    tools = [line.strip("- ").strip() for line in result.split("\n") if line.strip()]
    return tools[:5]

def llm_normalize_tool_name(user_tool_input):
    """Normalize tool names to avoid duplicates (drill vs driller)"""
    prompt = f"""User typed: "{user_tool_input}"

Normalize this to a standard, general tool name. Examples:
"big drill" → "Heavy Power Drill"
"driller" → "Power Drill"
"screw driver" → "Screwdriver Set"
"tape" -> "Teflon Tape"

Return ONLY the normalized tool name:"""

    return run_llm(prompt, max_new_tokens=20)

# --- SMART WORKER MATCHING ---

def calculate_worker_score(worker, cw_name, required_tools):
    """
    Calculate comprehensive worker score based on:
    - Canonical Work specific skill score (60%)
    - Global reputation (20%)
    - Tool availability (20%)
    """
    # 1. CW-specific skill score
    cw_skill_data = worker.get("cwSkillScore", {}).get(cw_name, {})
    cw_score = float(cw_skill_data.get("score", 0.0)) # 0.0 to 5.0

    # 2. Global rating
    global_rating = float(worker.get("avgRating", 0.0)) # 0.0 to 5.0

    # 3. Tool availability score
    worker_tools = set(worker.get("toolsAvailable", []))
    required_tools_set = set(required_tools)

    if required_tools_set:
        tool_match_ratio = len(worker_tools & required_tools_set) / len(required_tools_set)
    else:
        tool_match_ratio = 1.0  # No tools required

    tool_score = tool_match_ratio * 5.0  # Scale to 0-5

    # Weighted final score
    final_score = (cw_score * 0.6) + (global_rating * 0.2) + (tool_score * 0.2)

    return {
        "finalScore": final_score,
        "cwScore": cw_score,
        "globalRating": global_rating,
        "toolScore": tool_score,
        "toolMatchRatio": tool_match_ratio
    }

def get_best_workers_for_job(cw_name, required_tools, top_k=5):
    """
    Smart worker matching using Firestore query and local scoring.
    """
    try:
        # Step 1: Query workers who list this canonical work
        docs = db.collection(COL_WORKERS)\
            .where("canonicalWorks", "array_contains", cw_name)\
            .where("isActive", "==", True)\
            .limit(100).stream() # Limit to a reasonable number for scoring

        candidates = []
        for doc in docs:
            worker = doc.to_dict()
            worker_id = worker.get("uid") or doc.id

            score_breakdown = calculate_worker_score(worker, cw_name, required_tools)

            candidates.append({
                "workerId": worker_id,
                "score": score_breakdown["finalScore"],
                "breakdown": score_breakdown,
                "name": worker.get("name"),
                "phone": worker.get("phone")
            })

        # Step 2: Sort by final score
        candidates.sort(key=lambda x: x["score"], reverse=True)
        return candidates[:top_k]

    except Exception as e:
        print(f"Smart matching error: {e}")
        return []

# --- TRANSACTIONAL HELPERS ---

@transactional
def cancel_booking_in_transaction(tx, booking_ref, cancelled_by, reason):
    """Atomically cancels a booking and restores worker availability"""
    booking_snap = booking_ref.get(transaction=tx)
    if not booking_snap.exists:
        raise Exception("BOOKING_NOT_FOUND")

    booking = booking_snap.to_dict()
    current_status = booking.get("status")

    if current_status not in ["b1", "b2", "a1", "w1", "w2", "e1"]:
        raise Exception(f"CANNOT_CANCEL: Job is in status '{current_status}'")

    now = datetime.now(timezone.utc)

    # Restore worker availability if assigned (status 'a1' or later)
    if booking.get("workerId") and booking.get("date"):
        worker_id = booking["workerId"]
        date_id = booking["date"]

        start_hour = int(booking.get("startHour"))
        end_hour = int(booking.get("endHour"))
        time_slot_mask = hours_to_mask(start_hour, end_hour)

        avail_ref = db.collection(COL_WORKERS).document(worker_id)\
            .collection("availability").document(date_id)
        avail_snap = avail_ref.get(transaction=tx)

        if avail_snap.exists:
            current_mask = int(avail_snap.to_dict().get("mask", FULL_MASK))
            new_mask = current_mask | time_slot_mask  # Restore hours
            tx.update(avail_ref, {"mask": new_mask, "updatedAt": now_ts()})

        # Also update the worker request status
        req_ref = booking_ref.collection("workerRequests").document(worker_id)
        tx.update(req_ref, {"status": "cancelled_by_system", "updatedAt": now_ts()})

        tx.update(booking_ref, {"workerId": None, "assignedWorker": None}) # Clear assignment

    # Update booking status
    tx.update(booking_ref, {
        "status": "cancelled",
        "cancelledAt": now_ts(),
        "cancellationReason": reason,
        "updatedAt": now_ts(),
        "log.actions": firestore.ArrayUnion([{
            "ts": now,
            "actor": cancelled_by,
            "action": "cancelled",
            "info": {"reason": reason, "previousStatus": current_status}
        }])
    })

    return True

@transactional
def accept_booking_in_transaction(tx, booking_ref, req_ref, worker_id):
    """Atomically accepts a booking and blocks worker availability"""
    b_snap = booking_ref.get(transaction=tx)
    if not b_snap.exists:
        raise Exception("BOOKING_NOT_FOUND")
    booking = b_snap.to_dict()

    req_snap = req_ref.get(transaction=tx)
    if not req_snap.exists:
        raise Exception("NOT_INVITED")

    if booking.get("assignedWorker"):
        raise Exception("ALREADY_ASSIGNED")
    if booking.get("status") not in ("b1", "b2"):
        raise Exception("BOOKING_NOT_PENDING")

    # Check and block availability
    avail_ref = db.collection(COL_WORKERS).document(worker_id)\
        .collection("availability").document(booking["date"])
    avail_snap = avail_ref.get(transaction=tx)

    current_mask = FULL_MASK
    if avail_snap.exists:
        current_mask = int(avail_snap.to_dict().get("mask", FULL_MASK))

    needed_mask = hours_to_mask(booking["startHour"], booking["endHour"])

    if (current_mask & needed_mask) != needed_mask:
        tx.update(req_ref, {"status": "rejected", "updatedAt": now_ts()})
        raise Exception("WORKER_NOT_AVAILABLE")

    # Accept booking
    tx.update(booking_ref, {
        "assignedWorker": worker_id,
        "workerId": worker_id,
        "status": "a1",
        "assignedAt": now_ts(),
        "updatedAt": now_ts()
    })

    tx.update(req_ref, {
        "status": "accepted",
        "acceptedAt": now_ts(),
        "updatedAt": now_ts()
    })

    # Expire other requests
    all_reqs = booking_ref.collection("workerRequests").stream(transaction=tx)
    for req in all_reqs:
        if req.id != worker_id:
            tx.update(req.reference, {"status": "expired", "updatedAt": now_ts()})

    # Block worker availability
    new_mask = current_mask & (~needed_mask)
    tx.set(avail_ref, {"mask": new_mask, "updatedAt": now_ts()}, merge=True)

    # Log action
    log_time = datetime.now(timezone.utc)
    tx.update(booking_ref, {
        "log.actions": firestore.ArrayUnion([{
            "ts": log_time,
            "actor": worker_id,
            "action": "accepted",
            "info": {"startHour": booking["startHour"], "endHour": booking["endHour"]}
        }])
    })

    return True

@transactional
def submit_rating_in_transaction(tx, booking_ref, worker_ref, user_id, rating, review):
    """Atomically updates booking rating and worker stats"""
    booking_snap = booking_ref.get(transaction=tx)
    if not booking_snap.exists:
        raise Exception("Booking not found")
    booking_data = booking_snap.to_dict()

    worker_snap = worker_ref.get(transaction=tx)
    if not worker_snap.exists:
        raise Exception("Worker not found")
    worker_data = worker_snap.to_dict()

    if booking_data.get("userId") != user_id:
        raise Exception("Not authorized")
    if booking_data.get("rating", 0) > 0:
        raise Exception("Already rated")
    if booking_data.get("status") not in ["e3", "r1"]:
        raise Exception("Job not eligible for rating")

    cw_name = booking_data.get("serviceType", "General")

    # 1. Update worker global average rating
    old_avg = float(worker_data.get("avgRating", 0.0))
    job_count = int(worker_data.get("completedBookings", 0))

    if job_count == 0:
        new_global_avg = rating
    else:
        # Use simple rolling average calculation
        # Note: If this function runs AFTER verify-end-otp, job_count is already incremented.
        # We assume job_count here is the *new* count.
        old_total_score = old_avg * (job_count - 1)
        new_global_avg = (old_total_score + rating) / job_count

    tx.update(worker_ref, {
        "avgRating": new_global_avg,
        "updatedAt": now_ts()
    })

    # 2. Update CW-specific skill score (This is safer to do outside of the worker profile
    # document update to avoid conflicts, but keeping it here for simplicity of two updates)
    skill_map = worker_data.get("cwSkillScore", {})
    if cw_name in skill_map and job_count > 0:
        # Update CW-specific skill score based on rating
        curr_task_rating = skill_map[cw_name].get("score", 0.0)
        task_count = skill_map[cw_name].get("jobsCompleted", 0)

        # Recalculate task average. Task count is also already incremented in verify-end-otp
        # We assume task_count here is the *new* count.
        if task_count > 0:
            old_task_total = curr_task_rating * (task_count - 1)
            new_task_avg = (old_task_total + rating) / task_count

            # Update skill score for the canonical work (e.g., in worker's profile)
            skill_map[cw_name]["score"] = new_task_avg

            tx.update(worker_ref, {f"cwSkillScore.{cw_name}.score": new_task_avg})

    # 3. Update booking status/rating
    tx.update(booking_ref, {
        "rating": rating,
        "review": review,
        "status": "r1", # Rated
        "updatedAt": now_ts()
    })

    return True

# --- ROUTES: AUTH & ONBOARDING ---

@app.route("/generate-otp", methods=["POST"])
def generate_otp():
    secret = request.headers.get("x-secret-key")
    if secret != API_SECRET:
        return jsonify({"error": "Unauthorized"}), 401

    phone = request.json.get("phone")
    if not phone:
        return jsonify({"error": "Phone required"}), 400

    sanitized = sanitize_phone(phone)
    code = gen_otp(6)
    cid = str(uuid.uuid4())
    expires = int((datetime.now(timezone.utc) + timedelta(minutes=5)).timestamp())

    try:
        db.collection(COL_OTP).document(sanitized).set({
            "hash": hash_code(code),
            "correlation_id": cid,
            "expires_at": expires,
            "sim_message": {"text": f"{code} is your OTP verification code."}
        })
        return jsonify({"ok": True, "correlation_id": cid}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/verify-otp-log", methods=["POST"])
def verify_otp_log():
    secret = request.headers.get("x-secret-key")
    if secret != API_SECRET:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.json
    phone = sanitize_phone(data.get("phone"))
    code = data.get("code")
    cid = data.get("correlation_id")

    doc_ref = db.collection(COL_OTP).document(phone)
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"valid": False, "error": "Expired"}), 400

    rec = doc.to_dict()
    if rec['hash'] != hash_code(code) or rec['correlation_id'] != cid:
        return jsonify({"valid": False, "error": "Invalid Code"}), 400

    db.collection(COL_VERIFIED).document(phone).set({
        "phone": phone,
        "correlation_id": cid,
        "verified_at": now_ts(),
        "status": "verified"
    })
    doc_ref.delete()
    return jsonify({"valid": True}), 200

@app.route("/complete-signup", methods=["POST"])
@require_secret
def complete_signup():
    """Enhanced signup with AI-powered skill extraction for workers"""
    data = request.json
    phone = sanitize_phone(data.get("phone"))
    password = data.get("password")
    name = data.get("name")
    is_worker = data.get("isWorker", False)

    if not db.collection(COL_VERIFIED).document(phone).get().exists:
        return jsonify({"error": "Verification failed"}), 403

    try:
        # Use phone as UID for simplicity (Firebase Custom Auth integration)
        uid = phone
        try:
            # Create/Update Firebase Auth User
            auth.create_user(
                uid=uid,
                email=f"{phone}{EMAIL_SUFFIX}",
                password=password,
                display_name=name
            )
        except auth.EmailAlreadyExistsError:
            pass # User exists, proceed with profile update
        except Exception as e:
            return jsonify({"error": f"Firebase Auth Error: {e}"}), 500

        coll = COL_WORKERS if is_worker else COL_USERS
        profile = {
            "uid": uid,
            "phone": phone,
            "name": name,
            "pincode": data.get("pin"),
            "locality": data.get("locality"),
            "role": "worker" if is_worker else "user",
            "createdAt": now_ts(),
            "updatedAt": now_ts(),
            "isActive": True
        }

        if is_worker:
            desc = data.get("profileDescription", "")
            hourly = int(data.get("hourlyRate", 300))
            manual_tools = set(data.get("toolsAvailable", []))

            worker_extras = {
                "availability": "Y",
                "avgRating": 5.0, # Start with full rating
                "completedBookings": 0,
                "perHourCharge": hourly,
                "canonicalWorks": [],
                "cwSkillScore": {},
                "toolsAvailable": []
            }
            profile.update(worker_extras)

            # AI-powered skill extraction
            if desc:
                entities = extract_entities(desc)
                embedding = pinecone_embed_text(desc)

                # Use LLM-based hierarchical analysis from the first code block
                ai_jobs = analyze_worker_profile_hierarchical(desc)

                all_canonical_works = []
                all_tools_accumulated = set()

                for job in ai_jobs:
                    category = job.get("category", "General").strip()
                    task = job.get("task", "General Task").strip()
                    required_tools = set(job.get("tools", []))

                    # Determine actual tools based on user input
                    if manual_tools:
                        actual_tools = list(required_tools.intersection(manual_tools))
                    else:
                        actual_tools = list(required_tools)

                    # Fallback to general tool names if AI returns empty or manual tools mismatch
                    if not actual_tools and required_tools:
                         actual_tools = list(required_tools)

                    all_tools_accumulated.update(actual_tools)
                    all_canonical_works.append(task)

                    # Update cwSkillScore (using task as the CW name)
                    if task not in profile["cwSkillScore"]:
                         profile["cwSkillScore"][task] = {
                            "score": 5.0,
                            "jobsCompleted": 0
                        }

                profile["canonicalWorks"] = all_canonical_works
                profile["toolsAvailable"] = list(all_tools_accumulated)

                # Store new canonical works and upsert to Pinecone
                for cw_name in all_canonical_works:
                    cw_doc_ref = db.collection(COL_CW).document(slugify(cw_name))
                    if not cw_doc_ref.get().exists:
                        # If a new CW is detected, fetch its generic tool requirements
                        if cw_name not in profile["cwSkillScore"]: # Re-check to be safe
                            req_tools = llm_suggest_tools(cw_name)
                        else:
                            # Use tools suggested by the hierarchical analysis for this task
                            req_tools = [tool for job in ai_jobs if job.get("task") == cw_name for tool in job.get("tools", [])]

                        cw_doc = {
                            "canonicalWork": cw_name,
                            "description": desc,
                            "requiredTools": req_tools,
                            "jobsCompleted": 0,
                            "totalScore": 0.0,
                            "cwScore": 0.0,
                            "createdAt": now_ts(),
                            "createdBy": uid
                        }
                        db.collection(COL_CW).document(slugify(cw_name)).set(cw_doc, merge=True)

                        # Use the CW name and a clean description for embedding (for consumer side matching)
                        pinecone_upsert(slugify(cw_name), pinecone_embed_text(cw_name + " " + desc), {
                            "canonicalWork": cw_name,
                            "description": desc,
                            "requiredTools": req_tools
                        })


        # Save final profile
        db.collection(coll).document(uid).set(profile, merge=True)
        db.collection(COL_VERIFIED).document(phone).delete()

        return jsonify({"ok": True, "uid": uid, "profile": profile}), 200

    except Exception as e:
        print(f"Signup Error: {e}")
        return jsonify({"error": str(e)}), 500

def analyze_worker_profile_hierarchical(description):
    """
    Analyzes profile text and returns a list of Skill Categories with Sub-Jobs.
    Output structure:
    [
      {
        "category": "Plumber",
        "task": "Tap Repair",
        "tools": ["Wrench", "Teflon Tape"]
      },
      ...
    ]
    """
    prompt = f"""Analyze the following worker description: "{description}"

    Identify the specific jobs they do. For EACH job, determine:
    1. Broad Category (e.g. Plumber, Electrician, Carpenter)
    2. Specific Task (e.g. Tap Repair, Fan Installation, Furniture Polish). Keep the task name concise.
    3. Required Tools (List of 3-5 essential tools)

    Return a valid JSON list of objects. Example:
    [
      {{"category": "Plumber", "task": "Pipe Fixing", "tools": ["Wrench", "Sealant"]}},
      {{"category": "Electrician", "task": "Switch Replacement", "tools": ["Screwdriver", "Tester"]}}
    ]

    JSON:"""

    response = run_llm(prompt, max_new_tokens=400)

    # Cleaning JSON response if LLM adds markdown
    try:
        if "```json" in response:
            response = response.split("```json")[1].split("```")[0]
        elif "```" in response:
            # Assuming the full response is the JSON if no json marker is found,
            # or split on the first ``` if it's not explicitly ```json
            if response.startswith("[") or response.startswith("{"):
                pass
            else:
                 response = response.split("```")[1].split("```")[0]

        data = json.loads(response)
        return data
    except Exception as e:
        print(f"LLM Parse Error in hierarchical analysis: {e} | Raw: {response}")
        return []

# --- ROUTES: CANONICAL WORKS & TOOLS ---

@app.route("/cw/predict", methods=["POST"])
@require_secret
def predict_canonical_work():
    """AI-powered canonical work prediction from user description"""
    data = request.json
    text = data.get("text")

    if not text:
        return jsonify({"error": "text required"}), 400

    try:
        entities = extract_entities(text)
        embedding = pinecone_embed_text(text)

        # Search existing canonical works
        # Search is done against the embeddings created from CW documents
        matches = pinecone_query(embedding, top_k=3)

        if matches and matches[0]["score"] > 0.7:
            # High confidence match
            best_match = matches[0]["metadata"]
            cw_name = best_match.get("canonicalWork")
            req_tools = best_match.get("requiredTools", [])

            return jsonify({
                "canonicalWork": cw_name,
                "requiredTools": req_tools,
                "confidence": matches[0]["score"],
                "isNew": False,
                "alternatives": [m["metadata"] for m in matches[1:]]
            }), 200
        else:
            # Generate new canonical work
            cw_name = llm_generate_canonical_work(text, entities)
            req_tools = llm_suggest_tools(cw_name, text)

            return jsonify({
                "canonicalWork": cw_name,
                "requiredTools": req_tools,
                "confidence": 0.0,
                "isNew": True,
                "suggestedByAI": True
            }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/tools/normalize", methods=["POST"])
@require_secret
def normalize_tool():
    """Normalize tool names to avoid duplicates"""
    data = request.json
    tool_input = data.get("toolName")

    if not tool_input:
        return jsonify({"error": "toolName required"}), 400

    try:
        normalized = llm_normalize_tool_name(tool_input)
        return jsonify({"original": tool_input, "normalized": normalized}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --- ROUTES: BOOKING & TRANSACTIONS ---

@app.route("/create-booking", methods=["POST"])
@require_secret
def create_booking():
    """Enhanced booking creation with smart worker matching"""
    data = request.json
    user_id = data.get("userId")
    candidate_workers = data.get("candidateWorkers", [])

    # Step 1: Determine Canonical Work and Required Tools
    service_type = data.get("serviceType", "General")
    notes = data.get("notes", "")
    required_tools = []

    try:
        if not service_type or service_type == "General":
            embedding = pinecone_embed_text(notes)
            matches = pinecone_query(embedding, top_k=1)

            if matches and matches[0]["score"] > 0.6:
                service_type = matches[0]["metadata"].get("canonicalWork")
                required_tools = matches[0]["metadata"].get("requiredTools", [])
            else:
                # Fallback to LLM if vector match is low
                service_type = llm_generate_canonical_work(notes)
                required_tools = llm_suggest_tools(service_type, notes)
        else:
            # Service type provided, fetch tools from CW collection
            cw_docs = db.collection(COL_CW)\
                .where("canonicalWork", "==", service_type)\
                .limit(1).stream()

            for doc in cw_docs:
                required_tools = doc.to_dict().get("requiredTools", [])
                break

        data["serviceType"] = service_type

    except Exception as e:
        print(f"CW determination/tool fetching error: {e}")
        # Proceed with defaults if AI/DB fails
        pass

    # Step 2: Smart matching if no candidates provided
    if not candidate_workers:
        best_workers = get_best_workers_for_job(service_type, required_tools, top_k=5)
        candidate_workers = [w["workerId"] for w in best_workers]
        data["candidateWorkersDetails"] = best_workers # Attach for logging/debugging

    if not candidate_workers:
        return jsonify({"error": f"No workers found for {service_type}"}), 404

    # Step 3: Create Booking Record and Worker Requests
    try:
        date_str = data["date"]
        start_hour = int(data["startHour"])
        end_hour = int(data["endHour"])
        wage = int(data["wage"])
        hours = end_hour - start_hour

        # Create appointment datetime
        dt_obj = datetime.strptime(date_str, "%Y-%m-%d")
        # Ensure correct timezone awareness for Firestore/scheduling
        appt_dt = dt_obj.replace(hour=start_hour, minute=0, second=0, tzinfo=timezone.utc)

        booking_ref = db.collection(COL_BOOKINGS).document()
        booking_id = booking_ref.id
        now = now_ts()

        booking_obj = {
            "userId": user_id,
            "userPhone": sanitize_phone(data.get("userPhone")),
            "workerId": None,
            "status": "b1", # Pending Worker Selection
            "date": date_str,
            "appointmentDate": appt_dt,
            "startHour": start_hour,
            "endHour": end_hour,
            "serviceType": data.get("serviceType"),
            "wage": wage,
            "notes": data.get("notes"),
            "location": data.get("location"),
            "candidateWorkers": candidate_workers,
            "requiredTools": required_tools,
            "createdAt": now,
            "updatedAt": now,
            "log": {"actions": []},
            "payment": {
                "status": "pending",
                "method": data.get("paymentMethod", "cash")
            }
        }

        batch = db.batch()
        batch.set(booking_ref, booking_obj)

        # Create worker requests and simulate SMS
        for wid in candidate_workers:
            # Fetch worker's hourly rate for wage per hour calculation
            w_doc = db.collection(COL_WORKERS).document(wid).get()
            w_ph_rate = w_doc.to_dict().get("perHourCharge", 0) if w_doc.exists else 0

            wr_ref = booking_ref.collection("workerRequests").document(wid)
            batch.set(wr_ref, {
                "workerId": wid,
                "status": "pending",
                "sentAt": now,
                "sim_message": {
                    "text": sim_sms_message(
                        T_JOB_ALERT,
                        role=data.get("serviceType"),
                        locality=data.get("location", {}).get("locality", "Location"),
                        date=date_str,
                        from_time=f"{start_hour:02d}:00", # Format hours
                        to_time=f"{end_hour:02d}:00",
                        wage=wage,
                        details=data.get("notes"),
                        hours=hours,
                        missed_call_no=MISSED_CALL_NO
                    )
                }
            })

        batch.update(booking_ref, {"status": "b2"}) # Sent Requests
        batch.commit()

        return jsonify({
            "ok": True,
            "bookingId": booking_id,
            "serviceType": service_type,
            "matched": len(candidate_workers)
        }), 200

    except Exception as e:
        print(f"Booking creation error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/worker-accept", methods=["POST"])
@require_secret
def worker_accept():
    data = request.json
    wid = data["workerId"]
    bid = data["bookingId"]
    b_ref = db.collection(COL_BOOKINGS).document(bid)

    try:
        transaction = db.transaction()
        accept_booking_in_transaction(
            transaction,
            b_ref,
            b_ref.collection("workerRequests").document(wid),
            wid
        )
        return jsonify({"ok": True}), 200
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400

@app.route("/worker-reject", methods=["POST"])
@require_secret
def worker_reject():
    data = request.json
    wid = data["workerId"]
    bid = data["bookingId"]

    try:
        db.collection(COL_BOOKINGS)\
            .document(bid)\
            .collection("workerRequests")\
            .document(wid)\
            .update({"status": "rejected", "updatedAt": now_ts()})
        return jsonify({"ok": True}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --- JOB LIFECYCLE ROUTES ---

@app.route("/generate-start-otp", methods=["POST"])
@require_secret
def generate_start_otp():
    data = request.json
    bid = data["bookingId"]

    booking = db.collection(COL_BOOKINGS).document(bid).get().to_dict()
    worker_id = booking["workerId"]
    w_doc = db.collection(COL_WORKERS).document(worker_id).get()
    w_phone = sanitize_phone(w_doc.get("phone"))

    code = gen_otp(6)
    cid = str(uuid.uuid4())

    # Calculate est wage per hour for SMS
    hours = booking["endHour"] - booking["startHour"]
    wph = booking["wage"] // hours if hours > 0 else 0

    sim_text = sim_sms_message(
        T_START_OTP,
        locality=booking["location"]["locality"],
        date=booking["date"],
        from_time=f"{booking['startHour']:02d}:00",
        to_time=f"{booking['endHour']:02d}:00",
        otp=code,
        wage=booking["wage"],
        wph=wph
    )

    db.collection(COL_OTP).document(w_phone).set({
        "hash": hash_code(code),
        "correlation_id": cid,
        "expires_at": int((datetime.now(timezone.utc) + timedelta(minutes=15)).timestamp()),
        "sim_message": {"text": sim_text}
    })

    db.collection(COL_BOOKINGS).document(bid).update({
        "status": "w1", # OTP Sent
        "startOTPCorrelationId": cid
    })

    db.collection(COL_BOOKINGS).document(bid)\
        .collection("otpEvents").document(cid).set({
            "type": "start",
            "otpHash": hash_code(code),
            "verified": False,
            "generatedAt": now_ts()
        })

    return jsonify({"ok": True, "correlationId": cid}), 200

@app.route("/verify-start-otp", methods=["POST"])
@require_secret
def verify_start_otp():
    data = request.json
    bid = data["bookingId"]
    cid = data["correlationId"]
    code = data["code"]

    evt_ref = db.collection(COL_BOOKINGS).document(bid)\
        .collection("otpEvents").document(cid)
    evt = evt_ref.get()

    if not evt.exists:
        return jsonify({"valid": False, "error": "OTP not found"}), 400

    evt_data = evt.to_dict()

    if hash_code(code) == evt_data["otpHash"]:
        evt_ref.update({"verified": True, "verifiedAt": now_ts()})
        db.collection(COL_BOOKINGS).document(bid).update({
            "status": "w2", # Work Started
            "workStartedAt": now_ts()
        })
        return jsonify({"valid": True}), 200

    return jsonify({"valid": False, "error": "Invalid code"}), 400

@app.route("/generate-end-otp", methods=["POST"])
@require_secret
def generate_end_otp():
    data = request.json
    bid = data["bookingId"]

    booking = db.collection(COL_BOOKINGS).document(bid).get().to_dict()

    worker_doc = db.collection(COL_WORKERS).document(booking["workerId"]).get()
    w_phone = sanitize_phone(worker_doc.get("phone"))

    code = gen_otp(6)
    cid = str(uuid.uuid4())

    # Calculate actual hours worked (simplified to estimated hours for SMS)
    hours = booking["endHour"] - booking["startHour"]

    sim_text = sim_sms_message(
        T_END_OTP,
        locality=booking["location"]["locality"],
        date=booking["date"],
        otp=code,
        wage=booking["wage"],
        hours=hours
    )

    db.collection(COL_OTP).document(w_phone).set({
        "hash": hash_code(code),
        "correlation_id": cid,
        "expires_at": int((datetime.now(timezone.utc) + timedelta(minutes=15)).timestamp()),
        "sim_message": {"text": sim_text}
    })

    db.collection(COL_BOOKINGS).document(bid).update({
        "status": "e1", # Job Ended, OTP Sent
        "endOTPCorrelationId": cid
    })

    db.collection(COL_BOOKINGS).document(bid)\
        .collection("otpEvents").document(cid).set({
            "type": "end",
            "otpHash": hash_code(code),
            "verified": False,
            "generatedAt": now_ts()
        })

    return jsonify({"ok": True, "correlationId": cid}), 200

@app.route("/verify-end-otp", methods=["POST"])
@require_secret
def verify_end_otp():
    data = request.json
    bid = data["bookingId"]
    cid = data["correlationId"]
    code = data["code"]

    b_ref = db.collection(COL_BOOKINGS).document(bid)
    evt_ref = b_ref.collection("otpEvents").document(cid)
    evt = evt_ref.get()

    if not evt.exists:
        return jsonify({"valid": False, "error": "OTP not found"}), 400

    evt_data = evt.to_dict()

    if hash_code(code) == evt_data["otpHash"]:
        evt_ref.update({"verified": True, "verifiedAt": now_ts()})

        booking = b_ref.get().to_dict()
        worker_id = booking["workerId"]
        cw_name = booking.get("serviceType", "General")

        b_ref.update({
            "status": "e3", # Completed, Payment Pending/Received
            "completedAt": now_ts(),
            "payment.status": "paid" if data.get("paymentReceived") else "pending"
        })

        # Update worker stats: Completed bookings
        w_ref = db.collection(COL_WORKERS).document(worker_id)
        w_ref.update({"completedBookings": firestore.Increment(1)})

        try:
            # Update CW-specific skill score (increment jobsCompleted, slightly boost score)
            w_doc = w_ref.get().to_dict()
            skill_map = w_doc.get("cwSkillScore", {})

            if cw_name in skill_map:
                curr_score = skill_map[cw_name].get("score", 0)
                # Small increase for successful completion before rating
                new_score = min(5.0, curr_score + 0.05)

                # Use dot notation for atomic update of nested field
                w_ref.update({
                    f"cwSkillScore.{cw_name}.score": new_score,
                    f"cwSkillScore.{cw_name}.jobsCompleted": firestore.Increment(1)
                })
            else:
                # If CW wasn't in the map (e.g. dynamic job), add it
                w_ref.update({
                    f"cwSkillScore.{cw_name}": {"score": 4.0, "jobsCompleted": 1}
                })

            # Update global CW stats
            cw_docs = db.collection(COL_CW)\
                .where("canonicalWork", "==", cw_name)\
                .limit(1).stream()
            for cd in cw_docs:
                cd.reference.update({"jobsCompleted": firestore.Increment(1)})
        except Exception as e:
            print(f"Skill update error: {e}")

        return jsonify({"valid": True}), 200

    return jsonify({"valid": False, "error": "Invalid code"}), 400

@app.route("/submit-rating", methods=["POST"])
@require_secret
def submit_rating():
    data = request.json
    bid = data["bookingId"]
    rating = float(data["rating"])
    worker_id = data["workerId"]
    user_id = data["userId"]

    b_ref = db.collection(COL_BOOKINGS).document(bid)
    w_ref = db.collection(COL_WORKERS).document(worker_id)

    try:
        transaction = db.transaction()
        submit_rating_in_transaction(
            transaction,
            b_ref,
            w_ref,
            user_id,
            rating,
            data.get("review", "")
        )
        return jsonify({"ok": True}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/cancel-booking", methods=["POST"])
@require_secret
def cancel_booking():
    data = request.json
    booking_id = data.get("bookingId")
    user_id = data.get("userId")
    reason = data.get("reason", "User requested cancellation")

    try:
        booking_ref = db.collection(COL_BOOKINGS).document(booking_id)

        # Transactional cancel
        transaction = db.transaction()
        cancel_booking_in_transaction(transaction, booking_ref, user_id, reason)

        # Cleanup pending requests
        reqs = booking_ref.collection("workerRequests")\
            .where("status", "==", "pending").stream()
        batch = db.batch()
        has_updates = False

        for r in reqs:
            batch.update(r.reference, {
                "status": "cancelled_booking",
                "updatedAt": now_ts()
            })
            has_updates = True

        if has_updates:
            batch.commit()

        return jsonify({"ok": True}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route("/get-booking/<bookingId>", methods=["GET"])
@require_secret
def get_booking(bookingId):
    try:
        b = db.collection(COL_BOOKINGS).document(bookingId).get()
        if not b.exists:
            return jsonify({"error": "not found"}), 404

        doc = b.to_dict()
        reqs = [r.to_dict() for r in b.reference.collection("workerRequests").stream()]
        otps = [o.to_dict() for o in b.reference.collection("otpEvents").stream()]

        doc["workerRequests"] = reqs
        doc["otpEvents"] = otps
        return jsonify({"ok": True, "booking": doc}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/get-worker-availability", methods=["POST"])
@require_secret
def get_worker_availability():
    data = request.json
    wid = data["workerId"]
    date_id = data["date"]

    avail_doc = db.collection(COL_WORKERS).document(wid)\
        .collection("availability").document(date_id).get()

    current_mask = FULL_MASK
    if avail_doc.exists:
        current_mask = int(avail_doc.to_dict().get("mask", FULL_MASK))

    available_hours = []
    # Loop from 0 to 23 (SLOT_COUNT - 1)
    for i in range(SLOT_COUNT):
        # Check if the i-th bit is set
        if (current_mask >> i) & 1:
            available_hours.append(i + HOUR_OFFSET)

    return jsonify({"ok": True, "availableHours": available_hours}), 200

@app.route("/expire-requests", methods=["POST"])
@require_secret
def expire_requests():
    """Batch job to expire old pending requests."""
    data = request.json or {}
    # Default to 1 hour (3600 seconds)
    older = int(data.get("olderThanSeconds", 3600))
    cutoff_dt = datetime.now(timezone.utc) - timedelta(seconds=older)

    try:
        # Find bookings with pending status 'b2' (requests sent)
        q = db.collection(COL_BOOKINGS).where("status", "==", "b2").stream()
        updated_count = 0

        for b in q:
            # Check individual worker requests
            reqs = b.reference.collection("workerRequests")\
                .where("status", "==", "pending").stream()

            for r in reqs:
                r_data = r.to_dict()
                sent_at = r_data.get("sentAt")

                if isinstance(sent_at, datetime):
                    # Compare UTC-aware datetimes
                    if sent_at.replace(tzinfo=timezone.utc) < cutoff_dt.replace(tzinfo=timezone.utc):
                        r.reference.update({"status": "expired", "updatedAt": now_ts()})
                        updated_count += 1
                elif isinstance(sent_at, firestore.client.server_timestamp.ServerTimestamp):
                     # Cannot compare ServerTimestamp directly, skip or handle with a manual lookup
                     # or rely on a separate field if scheduled job is the primary expiry mechanism.
                     pass

        # Note: If all requests for a booking are expired/rejected,
        # a separate scheduler/logic should change the booking status from 'b2'
        # to 'c1' (No workers found) or re-run matching.

        return jsonify({"ok": True, "expired": updated_count}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --- HEALTH CHECK ---

@app.route("/", methods=["GET"])
def health_check():
    return jsonify({
        "status": "healthy",
        "service": "Kaarya Unified Backend",
        "version": "2.1",
        "features": [
            "AI-powered skill extraction (Hierarchical)",
            "Smart worker matching (CW Score, Global Rating, Tool Match)",
            "Vector-based job classification (Pinecone)",
            "Transactional updates (Cancellation, Acceptance, Rating)",
            "OTP-based job lifecycle"
        ]
    }), 200

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
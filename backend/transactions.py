# transactions.py
from datetime import datetime, timezone
from firebase_admin import firestore
from google.cloud.firestore_v1.transforms import ArrayUnion
from .firebase_init import db
from .constants import COL_WORKERS, COL_BOOKINGS
from .utils import now_ts, hours_to_mask, slugify

# --- TRANSACTIONAL HELPERS ---
@firestore.transactional
def cancel_booking_in_transaction(tx, booking_ref, cancelled_by, reason):
    snap = booking_ref.get(transaction=tx)
    if not snap.exists: raise Exception("BOOKING_NOT_FOUND")
    booking = snap.to_dict()
    if booking.get("status") in ["cancelled", "completed", "r1"]:
        raise Exception("CANNOT_CANCEL: Job is already complete or cancelled.")

    now_ts_val = now_ts()

    if booking.get("workerId") and booking.get("date"):
        wid = booking["workerId"]
        did = booking["date"]
        s = int(booking["startHour"])
        e = int(booking["endHour"])
        mask = hours_to_mask(s, e)

        avail_ref = db.collection(COL_WORKERS).document(wid).collection("availability").document(did)
        asnap = avail_ref.get(transaction=tx)

        if asnap.exists:
            curr = int(asnap.to_dict().get("mask", (1 << 24) - 1))
            tx.update(avail_ref, {"mask": curr | mask, "updatedAt": now_ts_val})

        tx.update(booking_ref, {"workerId": None, "assignedWorker": None})

    tx.update(booking_ref, {
        "status": "cancelled",
        "cancelledAt": now_ts_val,
        "cancellationReason": reason,
        "updatedAt": now_ts_val,
        "log.actions": ArrayUnion([{
            "ts": datetime.now(timezone.utc),
            "actor": cancelled_by,
            "action": "cancelled",
            "info": {"reason": reason, "previousStatus": booking.get("status")}
        }])
    })
    return True

@firestore.transactional
def accept_booking_in_transaction(tx, booking_ref, req_ref, worker_id):
    bsnap = booking_ref.get(transaction=tx)
    req_snap = req_ref.get(transaction=tx)

    if not bsnap.exists: raise Exception("BOOKING_NOT_FOUND")
    if not req_snap.exists: raise Exception("NOT_INVITED")
    booking = bsnap.to_dict()

    avail_ref = db.collection(COL_WORKERS).document(worker_id).collection("availability").document(booking["date"])
    asnap = avail_ref.get(transaction=tx)

    other_requests_to_expire = [
        r.reference
        for r in booking_ref.collection("workerRequests").stream(transaction=tx)
        if r.id != worker_id and r.to_dict().get("status") == "pending"
    ]

    curr = int(asnap.to_dict().get("mask", (1 << 24) - 1)) if asnap.exists else (1 << 24) - 1
    needed = hours_to_mask(int(booking["startHour"]), int(booking["endHour"]))

    if booking.get("assignedWorker"): raise Exception("ALREADY_ASSIGNED")
    if booking.get("status") not in ("b1", "b2"): raise Exception("BOOKING_NOT_PENDING")

    if (curr & needed) != needed:
        raise Exception("WORKER_NOT_AVAILABLE")

    now_ts_val = now_ts()

    tx.update(booking_ref, {
        "assignedWorker": worker_id,
        "workerId": worker_id,
        "status": "a1",
        "assignedAt": now_ts_val,
        "updatedAt": now_ts_val
    })

    tx.update(req_ref, {"status": "accepted", "acceptedAt": now_ts_val, "updatedAt": now_ts_val})

    for r_ref in other_requests_to_expire:
        tx.update(r_ref, {"status": "expired", "updatedAt": now_ts_val})

    tx.set(avail_ref, {"mask": curr & (~needed), "updatedAt": now_ts_val}, merge=True)

    tx.update(booking_ref, {
        "log.actions": ArrayUnion([{
            "ts": datetime.now(timezone.utc),
            "actor": worker_id,
            "action": "accepted",
            "info": {"startHour": booking["startHour"], "endHour": booking["endHour"]}
        }])
    })
    return True

@firestore.transactional
def submit_rating_healer_transaction(tx, booking_ref, worker_ref, user_id, raw_rating, adjusted_rating, prof_score, review, new_skills):
    booking_snap = booking_ref.get(transaction=tx)
    if not booking_snap.exists: raise Exception("Booking not found")
    booking_data = booking_snap.to_dict()

    worker_snap = worker_ref.get(transaction=tx)
    if not worker_snap.exists: raise Exception("Worker not found")
    worker_data = worker_snap.to_dict()

    if booking_data.get("userId") != user_id: raise Exception("Not authorized")
    if booking_data.get("rating", 0) > 0: raise Exception("Already rated")
    if booking_data.get("status") not in ["e3", "r1"]: raise Exception("Job not eligible for rating")

    cw_name = booking_data.get("serviceType", "General")
    job_count = int(worker_data.get("completedBookings", 0))

    # Calculate Global Averages using AI ADJUSTED rating
    old_avg = float(worker_data.get("avgRating", 0.0))
    old_prof = float(worker_data.get("professionalismScore", 5.0))
    
    if job_count > 0:
        new_global_avg = ((old_avg * (job_count - 1)) + adjusted_rating) / job_count
        new_prof_avg = ((old_prof * (job_count - 1)) + prof_score) / job_count
    else:
        new_global_avg = adjusted_rating
        new_prof_avg = prof_score

    now_ts_val = now_ts()
    
    # 1. Update Core Stats
    update_payload = {
        "avgRating": round(new_global_avg, 2),
        "professionalismScore": round(new_prof_avg, 2),
        "updatedAt": now_ts_val
    }

    # 2. Update Primary Skill Score (using AI adjusted rating)
    if cw_name in worker_data.get("cwSkillScore", {}):
        task_count = worker_data["cwSkillScore"][cw_name].get("jobsCompleted", 0)
        curr_task_rating = worker_data["cwSkillScore"][cw_name].get("score", 0.0)

        if task_count > 0:
            new_task_avg = adjusted_rating if task_count == 1 else ((curr_task_rating * (task_count - 1)) + adjusted_rating) / task_count
            update_payload[f"cwSkillScore.{cw_name}.score"] = round(new_task_avg, 2)
    
    # 3. PROFILE HEALER: Inject Discovered Skills
    existing_cws = set(worker_data.get("canonicalWorks", []))
    for skill in new_skills:
        s_name = skill['canonicalWork']
        s_cat = skill['category']
        s_slug = slugify(s_name)
        
        if s_name not in existing_cws:
            # Add to canonical works array
            tx.update(worker_ref, {"canonicalWorks": ArrayUnion([s_name])})
            
            # Initialize skill score for the newly discovered skill
            update_payload[f"cwSkillScore.{s_name}"] = {
                "score": round(adjusted_rating, 2), # Inherit the rating of the session they were discovered in
                "jobsCompleted": 1
            }
            
            # Setup cw_data structure
            update_payload[f"cw_data.{s_cat}.{s_slug}"] = {
                "name": s_name,
                "category": s_cat,
                "tools": skill.get("requiredTools", []),
                "rating": round(adjusted_rating, 2),
                "total_works": 1
            }

    tx.update(worker_ref, update_payload)

    # 4. Mark Booking Rated
    tx.update(booking_ref, {
        "rating": raw_rating, # Keep raw rating for customer history
        "aiAdjustedRating": adjusted_rating,
        "aiProfessionalismScore": prof_score,
        "review": review,
        "discoveredSkills": [s['canonicalWork'] for s in new_skills],
        "status": "r1",
        "updatedAt": now_ts_val
    })
    return True
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
API_SECRET = os.environ.get("OTP_API_SECRET", "HiFhGDorJRULc1Z")
FIREBASE_CRED = "firebase-service-account-key.json"
MISSED_CALL_NO = os.environ.get("MISSED_CALL_NO", "1234567890")
EMAIL_SUFFIX = "@kaaryaconnect.app"

# AI & Vector Config
HF_API_KEY = os.environ.get("HF_API_KEY", "")
PINECONE_API_KEY = os.environ.get("PINECONE_API_KEY", "")
PINECONE_HOST = os.environ.get("PINECONE_HOST", "https://llama-text-embed-v2-index-0s8x0bx.svc.aped-4627-b74a.pinecone.io")
# FIX 1: Explicitly define EMBEDDING_DIMENSION for vector operations
EMBEDDING_DIMENSION = 1024

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
COL_TOOLS = "tools"
COL_OTP = "otp"
COL_VERIFIED = "verified_signups"
COL_HISTORY = "raw_to_canonical_history"

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
    text = str(text).lower()
    text = re.sub(r'[^a-z0-9\s]+', '', text)
    text = re.sub(r'\s+', '_', text)
    return text.strip('_')

# --- HELPER FUNCTIONS: AI & VECTOR ---
def run_llm(prompt, max_new_tokens=200):
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
    if not PINECONE_API_KEY: return [0.0] * EMBEDDING_DIMENSION
    url = f"{PINECONE_HOST}/embed"
    payload = {
        "model": "llama-text-embed-v2",
        "inputs": [{"text": text}]
    }
    try:
        r = requests.post(url, headers=headers_pinecone, json=payload)
        if r.status_code != 200:
            print(f"Pinecone embed error: {r.status_code} {r.text}")
            return [0.0] * EMBEDDING_DIMENSION
        data = r.json()
        embeddings = data.get("data", [])
        if embeddings and len(embeddings) > 0:
            return embeddings[0].get("values", [0.0] * EMBEDDING_DIMENSION)
        return [0.0] * EMBEDDING_DIMENSION
    except Exception as e:
        print(f"Pinecone embed exception: {e}")
        return [0.0] * EMBEDDING_DIMENSION

def pinecone_upsert(vector_id, embedding, metadata):
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

# NEW: LLM Select for Vector Matches
def llm_select_best_match(user_input, candidates):
    """
    Asks LLM to strictly pick the best CW ID from vector search results.
    Returns the ID of the selected candidate, or 'NONE' if no good match.
    """
    candidates_str = ""
    for idx, c in enumerate(candidates):
        meta = c.get('metadata', {})
        candidates_str += f"{idx+1}. ID: {c.get('id')} | Name: {meta.get('canonicalWork', 'Unknown')} | Category: {meta.get('category', 'Unknown')}\n"
    prompt = f"""User Request: "{user_input}"
Available Job Types (from database):
{candidates_str}
Task: Identify which Job Type ID best matches the user request.
- If one matches well, return ONLY that ID.
- If none match well, return "NONE".
Answer (ID only):"""
    result = run_llm(prompt, max_new_tokens=20)
    # Clean and normalize the ID result
    result = result.strip().replace("ID:", "").strip()
    # Check if result is one of the candidate IDs
    valid_ids = [c.get('id') for c in candidates]
    if result in valid_ids:
        return result
    return None

def llm_generate_canonical_work(user_input, category="General"):
    # FIX 4: Corrected implementation to prompt LLM for both category and task
    prompt = f"""User description: "{user_input}"
Analyze the request.
1. Determine the best, single, broad Category (e.g., Plumber, Electrician...).
2. Create a clean, short, standardized Canonical Work name (3 words max) for the specific task.
Return a valid JSON object with ONLY two keys: `category` and `task`.
Example: {{"category": "Plumber", "task": "Tap Repair"}}"""
    response = run_llm(prompt, max_new_tokens=64)
    try:
        if "```json" in response:
            start = response.find("```json") + 7
            end = response.rfind("```")
            response = response[start:end].strip()
        elif "```" in response:
            response = response.split("```")[1].split("```")[0].strip()
        data = json.loads(response)
        task_name = data.get("task", user_input[:32]).strip()
        category_name = data.get("category", category).strip()
        if "\n" in task_name: task_name = task_name.split("\n")[0].strip()
        if "\n" in category_name: category_name = category_name.split("\n")[0].strip()
        return category_name, task_name
    except:
        print(f"LLM failed to return structured data. Raw: {response}")
        return category, user_input.split('.')[0].strip()[:32]

def llm_suggest_tools(canonical_work, description=""):
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
    prompt = f"""User typed: "{user_tool_input}"

Normalize this to a standard, general tool name. Examples:
"big drill" → "Heavy Power Drill"
"driller" → "Power Drill"
"screw driver" → "Screwdriver Set"
"tape" -> "Teflon Tape"

Return ONLY the normalized tool name:"""
    return run_llm(prompt, max_new_tokens=20)

def get_or_create_canonical_tool(raw_tool_name):
    raw_tool_name = str(raw_tool_name).strip()
    if len(raw_tool_name) < 2: return None

    embedding = pinecone_embed_text(raw_tool_name)
    matches = pinecone_query(embedding, top_k=1, filter_dict={"type": "tool"})

    if matches and matches[0]["score"] > 0.85:
        existing_tool = matches[0]["metadata"]
        print(f"🔧 Tool Match (Raw): '{raw_tool_name}' -> '{existing_tool['name']}' ({matches[0]['score']:.2f})")
        return existing_tool["name"]

    clean_name = llm_normalize_tool_name(raw_tool_name)
    if not clean_name or "LLM_ERROR" in clean_name or "LLM_DISABLED" in clean_name:
        clean_name = raw_tool_name

    clean_embedding = pinecone_embed_text(clean_name)
    clean_matches = pinecone_query(clean_embedding, top_k=1, filter_dict={"type": "tool"})

    if clean_matches and clean_matches[0]["score"] > 0.90:
        existing_tool = clean_matches[0]["metadata"]
        print(f"🔧 Tool Match (Clean): '{clean_name}' -> '{existing_tool['name']}'")
        return existing_tool["name"]

    print(f"🆕 Creating New Tool: {clean_name}")
    tool_id = slugify(clean_name)

    firestore_data = {
        "tool_id": tool_id,
        "name": clean_name,
        "type": "tool",
        "createdAt": now_ts(),
        "usageCount": 1
    }

    pinecone_metadata = {
        "tool_id": tool_id,
        "name": clean_name,
        "type": "tool"
    }

    db.collection(COL_TOOLS).document(tool_id).set(firestore_data, merge=True)

    pinecone_upsert(tool_id, clean_embedding, pinecone_metadata)

    return clean_name

def analyze_worker_profile_hierarchical(description):
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

    try:
        if "```json" in response:
            start_index = response.find("```json") + 7
            end_index = response.rfind("```")
            if start_index != -1 and end_index != -1 and start_index < end_index:
                response = response[start_index:end_index].strip()
            else:
                response = response.replace("```json", "").replace("```", "").strip()
        elif "```" in response:
             response = response.split("```")[1].split("```")[0].strip()

        data = json.loads(response)
        return data
    except Exception as e:
        print(f"LLM Parse Error in hierarchical analysis: {e} | Raw: {response}")
        return []

# --- GLOBAL CANONICAL WORK REGISTRY FUNCTIONS ---
def get_or_create_global_canonical_work(category, task):
    # FIX 2: Use deterministic slug as CW ID for reliable lookups
    cw_id = slugify(f"{category}_{task}")
    doc_ref = db.collection(COL_CW).document(cw_id)
    doc = doc_ref.get()

    if doc.exists:
        return doc.to_dict()

    print(f"Creating new Global CW: {category} - {task}")

    prompt = f"List 5 essential tools required for a {category} performing '{task}'. Comma separated."
    tools_str = run_llm(prompt, max_new_tokens=50)
    required_tools = [t.strip() for t in tools_str.split(',') if t.strip()]

    now_dt = datetime.now(timezone.utc)

    firestore_data = {
        "cw_id": cw_id,
        "canonicalWork": task,
        "category": category,
        "description": f"Standard {task} services by a {category}",
        "requiredTools": required_tools,
        "createdAt": now_ts(),
        "totalJobsGlobal": 0
    }

    pinecone_metadata = {
        "cw_id": cw_id,
        "canonicalWork": task,
        "category": category,
        "description": f"Standard {task} services by a {category}",
        "requiredTools": required_tools,
        "type": "job"
    }

    db.collection(COL_CW).document(cw_id).set(firestore_data)

    pinecone_upsert(cw_id, pinecone_embed_text(f"{category} {task}"), pinecone_metadata)

    serializable_data = firestore_data.copy()
    serializable_data["createdAt"] = now_dt.isoformat()

    return serializable_data

# --- SMART WORKER MATCHING ---
def calculate_worker_score(worker, cw_name, required_tools):
    """
    Calculate comprehensive worker score based on:
    - Canonical Work specific skill score (60%)
    - Global reputation (20%)
    - Tool availability (20%)
    """
    cw_score = float(worker.get("cwSkillScore", {}).get(cw_name, {}).get("score", 0.0))
    global_rating = float(worker.get("avgRating", 0.0))

    worker_tools = set(worker.get("toolsAvailable", []))
    required_set = set(required_tools)

    tool_match_ratio = 1.0
    if required_set:
        tool_match_ratio = len(worker_tools & required_set) / len(required_set)

    tool_score = tool_match_ratio * 5.0  # Scale to 0-5

    final_score = (cw_score * 0.6) + (global_rating * 0.2) + (tool_score * 0.2)

    return {
        "finalScore": final_score,
        "cwScore": cw_score,
        "toolScore": tool_score,
        "globalRating": global_rating
    }

def get_best_workers_for_job(cw_name, cw_category, required_tools, top_k=5):
    """
    Smart worker matching using Firestore query and local scoring, with fallback.
    """
    candidates = []

    # Strategy 1: Exact Canonical Work Match (Highest Confidence)
    try:
        docs = db.collection(COL_WORKERS)\
            .where("canonicalWorks", "array_contains", cw_name)\
            .where("isActive", "==", True)\
            .limit(50).stream()

        for doc in docs:
            w = doc.to_dict()
            score = calculate_worker_score(w, cw_name, required_tools)
            candidates.append({
                "workerId": doc.id,
                "score": score["finalScore"],
                "name": w.get("name"),
                "phone": w.get("phone"),
                "breakdown": score
            })

        if candidates:
            candidates.sort(key=lambda x: x["score"], reverse=True)
            # Return immediately if we have enough high-confidence candidates
            if len(candidates) >= top_k:
                 return candidates[:top_k]

    except Exception as e:
        print(f"Error during CW exact match query: {e}")

    # Strategy 2: Fallback to Broad Category Match (Lower Confidence, wider net)
    if cw_category and cw_category != "General":
        try:
            # Check a wider pool of active workers
            all_docs = db.collection(COL_WORKERS).where("isActive", "==", True).limit(200).stream()

            for doc in all_docs:
                w = doc.to_dict()

                # Check if worker is already in candidates list (skip to avoid double-scoring)
                if any(c["workerId"] == doc.id for c in candidates):
                    continue

                # Check if worker has expertise in this broad category
                if cw_category in w.get("cw_data", {}):
                    # Use best score from that category as baseline (max rating of any task in that category)
                    cat_scores = [float(x.get("rating", 0.0)) for x in w["cw_data"][cw_category].values()]
                    baseline = max(cat_scores) if cat_scores else 4.0 # Default to 4.0 if only cat exists but no tasks/ratings

                    # Create a simulated worker data structure for scoring
                    w_sim = w.copy()
                    # Assign the Category's baseline score to the CW that was requested
                    w_sim["cwSkillScore"] = {cw_name: {"score": baseline}}

                    # Recalculate score using the category baseline for the CW
                    score = calculate_worker_score(w_sim, cw_name, required_tools)

                    candidates.append({
                        "workerId": doc.id,
                        "score": score["finalScore"] * 0.95, # Slight penalty for category fallback
                        "name": w.get("name"),
                        "phone": w.get("phone"),
                        "breakdown": score
                    })

        except Exception as e:
            print(f"Error during Category fallback query: {e}")

    # Final sort and limit
    candidates.sort(key=lambda x: x["score"], reverse=True)
    return candidates[:top_k]


# --- TRANSACTIONAL HELPERS (Same as original) ---
@transactional
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
            curr = int(asnap.to_dict().get("mask", FULL_MASK))
            tx.update(avail_ref, {"mask": curr | mask, "updatedAt": now_ts_val})

        tx.update(booking_ref, {"workerId": None, "assignedWorker": None})

    tx.update(booking_ref, {
        "status": "cancelled",
        "cancelledAt": now_ts_val,
        "cancellationReason": reason,
        "updatedAt": now_ts_val,
        "log.actions": firestore.ArrayUnion([{
            "ts": datetime.now(timezone.utc),
            "actor": cancelled_by,
            "action": "cancelled",
            "info": {"reason": reason, "previousStatus": booking.get("status")}
        }])
    })
    return True

@transactional
def accept_booking_in_transaction(tx, booking_ref, req_ref, worker_id):
    # --- STEP 1: ALL READS FIRST (MUST BE CONTIGUOUS) ---
    # 1. Read Booking, Request, and Worker Availability (Primary Reads)
    bsnap = booking_ref.get(transaction=tx)
    req_snap = req_ref.get(transaction=tx)

    if not bsnap.exists: raise Exception("BOOKING_NOT_FOUND")
    if not req_snap.exists: raise Exception("NOT_INVITED")
    booking = bsnap.to_dict()

    # Read the availability document
    avail_ref = db.collection(COL_WORKERS).document(worker_id).collection("availability").document(booking["date"])
    asnap = avail_ref.get(transaction=tx)

    # 2. READ: Fetch references/IDs of OTHER worker requests for cleanup (Secondary Reads)
    # This must happen before any writes start. We only collect the references/IDs.
    other_requests_to_expire = [
        r.reference
        for r in booking_ref.collection("workerRequests").stream(transaction=tx)
        if r.id != worker_id and r.to_dict().get("status") == "pending"
    ]

    # Calculate current mask and needed mask
    curr = int(asnap.to_dict().get("mask", FULL_MASK)) if asnap.exists else FULL_MASK
    needed = hours_to_mask(int(booking["startHour"]), int(booking["endHour"]))

    # --- STEP 2: VALIDATION AND EARLY EXIT (No writes here) ---
    if booking.get("assignedWorker"): raise Exception("ALREADY_ASSIGNED")
    if booking.get("status") not in ("b1", "b2"): raise Exception("BOOKING_NOT_PENDING")

    if (curr & needed) != needed:
        # If unavailable, we simply raise. No tx.update() here.
        raise Exception("WORKER_NOT_AVAILABLE")

    # --- STEP 3: ALL WRITES ---
    now_ts_val = now_ts()

    # 1. Update Accepted Booking (WRITE 1)
    tx.update(booking_ref, {
        "assignedWorker": worker_id,
        "workerId": worker_id,
        "status": "a1",
        "assignedAt": now_ts_val,
        "updatedAt": now_ts_val
    })

    # 2. Update Accepted Worker Request (WRITE 2)
    tx.update(req_ref, {"status": "accepted", "acceptedAt": now_ts_val, "updatedAt": now_ts_val})

    # 3. Expire Other Requests (Cleanup Writes - using the references read earlier)
    for r_ref in other_requests_to_expire:
        tx.update(r_ref, {"status": "expired", "updatedAt": now_ts_val})

    # 4. Update Worker Availability Mask (Set bits to 0 for booked hours)
    tx.set(avail_ref, {"mask": curr & (~needed), "updatedAt": now_ts_val}, merge=True)

    # 5. Log Action
    tx.update(booking_ref, {
        "log.actions": firestore.ArrayUnion([{
            "ts": datetime.now(timezone.utc),
            "actor": worker_id,
            "action": "accepted",
            "info": {"startHour": booking["startHour"], "endHour": booking["endHour"]}
        }])
    })
    return True

@transactional
def submit_rating_in_transaction(tx, booking_ref, worker_ref, user_id, rating, review):
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

    # 1. Update worker global average rating
    old_avg = float(worker_data.get("avgRating", 0.0))
    if job_count > 0:
        old_total_score = old_avg * (job_count - 1)
        new_global_avg = (old_total_score + rating) / job_count
    else:
        new_global_avg = rating

    now_ts_val = now_ts()
    tx.update(worker_ref, {
        "avgRating": new_global_avg,
        "updatedAt": now_ts_val
    })

    # 2. Update CW-specific skill score
    if cw_name in worker_data.get("cwSkillScore", {}):
        task_count = worker_data["cwSkillScore"][cw_name].get("jobsCompleted", 0)
        curr_task_rating = worker_data["cwSkillScore"][cw_name].get("score", 0.0)

        if task_count > 0:
            if task_count == 1:
                new_task_avg = rating
            else:
                # Assuming curr_task_rating is the average of the *previous* jobs,
                # or a boosted score that we now correct to a true average.
                old_task_total = curr_task_rating * (task_count - 1)
                new_task_avg = (old_task_total + rating) / task_count

            tx.update(worker_ref, {f"cwSkillScore.{cw_name}.score": new_task_avg})

    # 3. Update booking status/rating
    tx.update(booking_ref, {
        "rating": rating,
        "review": review,
        "status": "r1", # Rated
        "updatedAt": now_ts_val
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
        print(f"Generate OTP Error: {e}")
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
    data = request.json
    phone = sanitize_phone(data.get("phone"))
    password = data.get("password")
    name = data.get("name")
    is_worker = data.get("isWorker", False)

    if not db.collection(COL_VERIFIED).document(phone).get().exists:
        return jsonify({"error": "Verification failed"}), 403

    try:
        uid = phone
        try:
            auth.create_user(
                uid=uid,
                email=f"{phone}{EMAIL_SUFFIX}",
                password=password,
                display_name=name
            )
        except auth.EmailAlreadyExistsError:
            pass
        except Exception as e:
            print(f"Firebase Auth Error: {e}")
            return jsonify({"error": f"Firebase Auth Error: {e}"}), 500

        now_dt = datetime.now(timezone.utc)
        now_ts_val = now_ts()

        coll = COL_WORKERS if is_worker else COL_USERS
        profile = {
            "uid": uid,
            "phone": phone,
            "name": name,
            "pincode": data.get("pin"),
            "locality": data.get("locality"),
            "role": "worker" if is_worker else "user",
            "createdAt": now_dt,
            "updatedAt": now_dt,
            "isActive": True
        }

        if is_worker:
            hourly = int(data.get("hourlyRate", 300))
            verified_skills_payload = data.get("verifiedSkills", [])
            all_raw_tools = set()
            tool_normalization_cache = {}

            # 1. First Pass: Collect all unique raw tools & normalize them
            for skill_entry in verified_skills_payload:
                raw_tools_for_skill = skill_entry.get("myTools", [])
                for tool in raw_tools_for_skill:
                    raw_tool_str = str(tool).strip()
                    if raw_tool_str and raw_tool_str not in tool_normalization_cache:
                        canonical_name = get_or_create_canonical_tool(raw_tool_str)
                        if canonical_name and canonical_name not in ("LLM_ERROR", "LLM_DISABLED"):
                            tool_normalization_cache[raw_tool_str] = canonical_name
                            all_raw_tools.add(canonical_name)

            profile["toolsAvailable"] = list(all_raw_tools)

            worker_extras = {
                "availability": "Y",
                "avgRating": 5.0,
                "completedBookings": 0,
                "perHourCharge": hourly,
                "canonicalWorks": [],
                "cwSkillScore": {},
            }
            profile.update(worker_extras)

            # 2. Second Pass: Structure skills and save global CW entries
            all_canonical_works = []
            cw_data_to_save = {}

            for skill_entry in verified_skills_payload:
                task = skill_entry.get("task", "General Task").strip()
                category = skill_entry.get("category", "General").strip()

                canonical_tools_for_task = [
                    tool_normalization_cache[str(t).strip()]
                    for t in skill_entry.get("myTools", [])
                    if str(t).strip() in tool_normalization_cache
                ]

                all_canonical_works.append(task)

                task_slug = slugify(task)
                if category not in cw_data_to_save:
                    cw_data_to_save[category] = {}

                cw_data_to_save[category][task_slug] = {
                    "name": task,
                    "category": category,
                    "tools": list(set(canonical_tools_for_task)),
                    "rating": 5.0,
                    "total_works": 0
                }

                if task not in profile["cwSkillScore"]:
                    profile["cwSkillScore"][task] = {"score": 5.0, "jobsCompleted": 0}

            profile["canonicalWorks"] = all_canonical_works
            profile["cw_data"] = cw_data_to_save

            # 3. CW Document Upsert Logic (only if CW does not exist)
            for cw_name in all_canonical_works:
                cw_slug = slugify(cw_name)
                cw_doc_ref = db.collection(COL_CW).document(cw_slug)

                cw_snap = cw_doc_ref.get()

                if not cw_snap.exists:
                    req_tools_global = list(profile["toolsAvailable"])

                    cw_doc = {
                        "canonicalWork": cw_name,
                        "description": data.get("profileDescription", ""),
                        "requiredTools": req_tools_global,
                        "jobsCompleted": 0,
                        "totalScore": 0.0,
                        "cwScore": 0.0,
                        "createdAt": now_dt,
                        "createdBy": uid
                    }

                    db.collection(COL_CW).document(cw_slug).set({
                        **cw_doc,
                        "createdAt": now_ts_val
                    }, merge=True)

                    pinecone_upsert(cw_slug, pinecone_embed_text(cw_name + " " + cw_doc["description"]), {
                        "canonicalWork": cw_name,
                        "description": cw_doc["description"],
                        "requiredTools": req_tools_global,
                        "type": "job"
                    })

        # Save final profile
        db_profile = profile.copy()
        db_profile["createdAt"] = now_ts_val
        db_profile["updatedAt"] = now_ts_val

        db.collection(coll).document(uid).set(db_profile, merge=True)
        db.collection(COL_VERIFIED).document(phone).delete()

        return jsonify({"ok": True, "uid": uid}), 200

    except Exception as e:
        print(f"Signup Error: {e}")
        return jsonify({"error": str(e)}), 500

# --- ROUTES: CANONICAL WORKS & TOOLS ---

@app.route("/cw/predict-multi", methods=["POST"])
@require_secret
def predict_multi_skills():
    data = request.json
    text = data.get("text")

    if not text:
        return jsonify({"error": "text required"}), 400

    # 1. Use AI to parse Hierarchy
    ai_jobs = analyze_worker_profile_hierarchical(text)

    results = []
    for job in ai_jobs:
        cat = job.get("category")
        task = job.get("task")

        if not cat or not task: continue

        # 2. Fetch/Create Standard Data
        try:
            global_cw = get_or_create_global_canonical_work(cat, task)
        except Exception as e:
            print(f"Error fetching/creating CW: {e}")
            continue

        results.append({
            "category": cat,
            "task": task,
            "cw_id": global_cw["cw_id"],
            "suggestedTools": global_cw["requiredTools"],
            "aiSuggestedToolsFromProfile": job.get("tools", [])
        })

    return jsonify({"predictions": results}), 200

@app.route("/cw/predict", methods=["POST"])
@require_secret
def predict_canonical_work():
    data = request.json
    text = data.get("text")

    if not text:
        return jsonify({"error": "text required"}), 400

    try:
        embedding = pinecone_embed_text(text)
        # Find 3 closest matches
        matches = pinecone_query(embedding, top_k=3, filter_dict={"type": "job"})

        selected_cw_data = None
        if matches and matches[0]["score"] > 0.7:
             # Use LLM to select best match from the 3 vector candidates
            selected_cw_id = llm_select_best_match(text, matches)
            if selected_cw_id:
                selected_cw_data = next((m['metadata'] for m in matches if m['id'] == selected_cw_id), None)

        if selected_cw_data:
            cw_name = selected_cw_data.get("canonicalWork")
            req_tools = selected_cw_data.get("requiredTools", [])
            confidence = next((m['score'] for m in matches if m['id'] == selected_cw_id), 0.0)

            return jsonify({
                "canonicalWork": cw_name,
                "requiredTools": req_tools,
                "confidence": confidence,
                "isNew": False,
                "alternatives": [m["metadata"] for m in matches if m['id'] != selected_cw_id]
            }), 200
        else:
            # Cold Start: LLM generates new CW name and category
            category, cw_name = llm_generate_canonical_work(text)
            global_cw = get_or_create_global_canonical_work(category, cw_name)
            req_tools = global_cw["requiredTools"]

            return jsonify({
                "canonicalWork": cw_name,
                "requiredTools": req_tools,
                "confidence": 0.0,
                "isNew": True,
                "suggestedByAI": True
            }), 200

    except Exception as e:
        print(f"Predict CW Error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/tools/normalize", methods=["POST"])
@require_secret
def normalize_tool():
    data = request.json
    tool_input = data.get("toolName")

    if not tool_input:
        return jsonify({"error": "toolName required"}), 400

    try:
        normalized = get_or_create_canonical_tool(tool_input)

        if normalized in ("LLM_ERROR", "LLM_DISABLED"):
            normalized = llm_normalize_tool_name(tool_input)

        return jsonify({"original": tool_input, "normalized": normalized}), 200
    except Exception as e:
        print(f"Normalize Tool Error: {e}")
        return jsonify({"error": str(e)}), 500

# --- ROUTES: BOOKING & TRANSACTIONS ---

@app.route("/create-booking", methods=["POST"])
@require_secret
def create_booking():
    data = request.json
    user_id = data.get("userId")
    candidate_workers_input = data.get("candidateWorkers", [])

    # Step 1: Determine Canonical Work, Category, and Required Tools
    notes = data.get("notes", "")
    service_type = data.get("serviceType", "General").strip()
    service_category = data.get("serviceCategory", "General").strip()
    required_tools = data.get("requiredTools", []) or []

    if not candidate_workers_input:
        if len(notes) < 20:
            return jsonify({"error": "Job description too short. Requires a minimum of 20 characters for accurate matching."}), 400

        # Vector Search: Find 3 closest existing CWs
        embedding = pinecone_embed_text(notes)
        matches = pinecone_query(embedding, top_k=3, filter_dict={"type": "job"})

        selected_cw_data = None

        # NOTE: Using a lower score threshold (e.g., 0.55) here might help prevent cold-start creation
        # when a close-enough CW already exists, but the LLM selection is the critical tie-breaker.
        if matches:
            # LLM Selection: Strictly pick the best match ID from top 3
            # This is critical to map vague user input to a canonical work even if the raw vector score is moderate.
            selected_cw_id = llm_select_best_match(notes, matches)

            if selected_cw_id and selected_cw_id != "NONE":
                # Match Found: Find the corresponding data from the matches list
                selected_cw_data = next((m['metadata'] for m in matches if m['id'] == selected_cw_id), None)

        if selected_cw_data:
            # Match Found: Use the CW details from the database
            service_type = selected_cw_data.get("canonicalWork", service_type)
            service_category = selected_cw_data.get("category", service_category)
            required_tools = selected_cw_data.get("requiredTools", required_tools)
        else:
            # Fallback to LLM to generate new CW (Cold Start)
            print(f"COLD START: Generating new CW for notes: {notes}")
            category, cw_name = llm_generate_canonical_work(notes)
            global_cw = get_or_create_global_canonical_work(category, cw_name)

            service_type = global_cw["canonicalWork"]
            service_category = global_cw["category"]
            required_tools = global_cw["requiredTools"]

        data["serviceType"] = service_type
        data["serviceCategory"] = service_category
        data["requiredTools"] = required_tools

    # Step 2: Smart matching if no candidates provided
    final_candidates = candidate_workers_input
    if not final_candidates:
        best_workers = get_best_workers_for_job(service_type, service_category, required_tools, top_k=5)
        final_candidates = [w["workerId"] for w in best_workers]
        data["candidateWorkersDetails"] = best_workers

    if not final_candidates:
        return jsonify({"error": f"No workers found for Canonical Work: {service_type} in category: {service_category}. Try simplifying your description or checking worker profiles."}), 404

    # Step 3: Create Booking Record and Worker Requests
    try:
        date_str = data["date"]
        start_hour = int(data["startHour"])
        end_hour = int(data["endHour"])
        wage = int(data["wage"])
        hours = end_hour - start_hour

        dt_obj = datetime.strptime(date_str, "%Y-%m-%d")
        # Use timezone.utc explicitly for Firestore Timestamp compatibility
        appt_dt = dt_obj.replace(hour=start_hour, minute=0, second=0, tzinfo=timezone.utc)

        booking_ref = db.collection(COL_BOOKINGS).document()
        booking_id = booking_ref.id
        now_ts_val = now_ts()

        booking_obj = {
            "userId": user_id,
            "userPhone": sanitize_phone(data.get("userPhone")),
            "workerId": None,
            "status": "b1",
            "date": date_str,
            "appointmentDate": appt_dt,
            "startHour": start_hour,
            "endHour": end_hour,
            "serviceType": service_type,
            "serviceCategory": service_category,
            "wage": wage,
            "notes": notes,
            "location": data.get("location"),
            "candidateWorkers": final_candidates,
            "requiredTools": required_tools,
            "createdAt": now_ts_val,
            "updatedAt": now_ts_val,
            "log": {"actions": []},
            "payment": {
                "status": "pending",
                "method": data.get("paymentMethod", "cash")
            }
        }

        batch = db.batch()
        batch.set(booking_ref, booking_obj)

        for wid in final_candidates:
            # Fetch worker data to get perHourCharge for message calculation/display
            w_doc_snap = db.collection(COL_WORKERS).document(wid).get()
            w_ph_rate = w_doc_snap.to_dict().get("perHourCharge", 0) if w_doc_snap.exists else 0

            wr_ref = booking_ref.collection("workerRequests").document(wid)
            batch.set(wr_ref, {
                "workerId": wid,
                "status": "pending",
                "sentAt": now_ts_val,
                "sim_message": {
                    "text": sim_sms_message(
                        T_JOB_ALERT,
                        role=service_type,
                        locality=data.get("location", {}).get("locality", "Location"),
                        date=date_str,
                        from_time=f"{start_hour:02d}:00",
                        to_time=f"{end_hour:02d}:00",
                        wage=wage,
                        details=notes,
                        hours=hours,
                        missed_call_no=MISSED_CALL_NO
                    )
                }
            })

        batch.update(booking_ref, {"status": "b2"}) # Move to "b2" after worker requests are created
        batch.commit()

        return jsonify({
            "ok": True,
            "bookingId": booking_id,
            "serviceType": service_type,
            "matched": len(final_candidates)
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
        # Success message when a worker accepts
        return jsonify({"ok": True, "message": "1 user request processed"}), 200
    except Exception as e:
        error_msg = str(e)
        print(f"Worker Accept Error: {error_msg}")

        # Check for the specific availability exception
        if "WORKER_NOT_AVAILABLE" in error_msg:
            # Return the specific error message you requested
            return jsonify({
                "ok": False,
                "error": f"Worker {wid} not available for given time try later",
                "message": "0 user requests processed"
            }), 400

        # Handle other errors (e.g., BOOKING_NOT_FOUND, ALREADY_ASSIGNED)
        return jsonify({"ok": False, "error": error_msg, "message": "Timeout"}), 400

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
        print(f"Worker Reject Error: {e}")
        return jsonify({"error": str(e)}), 500

# --- JOB LIFECYCLE ROUTES ---

@app.route("/generate-start-otp", methods=["POST"])
@require_secret
def generate_start_otp():
    data = request.json
    bid = data["bookingId"]

    try:
        booking_snap = db.collection(COL_BOOKINGS).document(bid).get()
        if not booking_snap.exists: return jsonify({"error": "Booking not found"}), 404
        booking = booking_snap.to_dict()

        if booking.get("status") not in ("a1", "w1"):
            return jsonify({"error": "Job not ready for start OTP"}), 400

        worker_id = booking["workerId"]
        w_doc_snap = db.collection(COL_WORKERS).document(worker_id).get()
        if not w_doc_snap.exists: return jsonify({"error": "Worker not found"}), 404
        w_doc = w_doc_snap.to_dict()

        w_phone = sanitize_phone(w_doc.get("phone"))
        if not w_phone: return jsonify({"error": "Worker phone missing"}), 400

        code = gen_otp(6)
        cid = str(uuid.uuid4())

        hours = booking["endHour"] - booking["startHour"]
        wph = booking["wage"] // hours if hours > 0 else 0

        sim_text = sim_sms_message(
            T_START_OTP,
            locality=booking.get("location", {}).get("locality", "Location"),
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

        batch = db.batch()
        b_ref = db.collection(COL_BOOKINGS).document(bid)
        batch.update(b_ref, {
            "status": "w1",
            "startOTPCorrelationId": cid
        })

        batch.set(b_ref.collection("otpEvents").document(cid), {
            "type": "start",
            "otpHash": hash_code(code),
            "verified": False,
            "generatedAt": now_ts()
        })
        batch.commit()

        return jsonify({"ok": True, "correlationId": cid}), 200

    except Exception as e:
        print(f"Generate Start OTP Error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/verify-start-otp", methods=["POST"])
@require_secret
def verify_start_otp():
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

    if evt_data.get("verified", False):
        return jsonify({"valid": True, "message": "Already verified"}), 200

    if hash_code(code) == evt_data["otpHash"]:
        batch = db.batch()
        batch.update(evt_ref, {"verified": True, "verifiedAt": now_ts()})
        batch.update(b_ref, {
            "status": "w2",
            "workStartedAt": now_ts()
        })
        batch.commit()

        return jsonify({"valid": True}), 200

    return jsonify({"valid": False, "error": "Invalid code"}), 400

@app.route("/generate-end-otp", methods=["POST"])
@require_secret
def generate_end_otp():
    data = request.json
    bid = data["bookingId"]

    try:
        booking_snap = db.collection(COL_BOOKINGS).document(bid).get()
        if not booking_snap.exists: return jsonify({"error": "Booking not found"}), 404
        booking = booking_snap.to_dict()

        if booking.get("status") != "w2":
            return jsonify({"error": "Job not in progress"}), 400

        worker_doc_snap = db.collection(COL_WORKERS).document(booking["workerId"]).get()
        if not worker_doc_snap.exists: return jsonify({"error": "Worker not found"}), 404
        w_doc = worker_doc_snap.to_dict()

        w_phone = sanitize_phone(w_doc.get("phone"))
        if not w_phone: return jsonify({"error": "Worker phone missing"}), 400

        code = gen_otp(6)
        cid = str(uuid.uuid4())

        start_ts = booking.get("workStartedAt")
        if isinstance(start_ts, datetime):
            elapsed_dt = datetime.now(timezone.utc) - start_ts.replace(tzinfo=timezone.utc)
            hours = elapsed_dt.total_seconds() / 3600
        else:
            hours = booking["endHour"] - booking["startHour"]

        display_hours = round(hours, 2)

        sim_text = sim_sms_message(
            T_END_OTP,
            locality=booking.get("location", {}).get("locality", "Location"),
            date=booking["date"],
            otp=code,
            wage=booking["wage"],
            hours=display_hours
        )

        db.collection(COL_OTP).document(w_phone).set({
            "hash": hash_code(code),
            "correlation_id": cid,
            "expires_at": int((datetime.now(timezone.utc) + timedelta(minutes=15)).timestamp()),
            "sim_message": {"text": sim_text}
        })

        batch = db.batch()
        b_ref = db.collection(COL_BOOKINGS).document(bid)
        batch.update(b_ref, {
            "status": "e1",
            "endOTPCorrelationId": cid
        })

        batch.set(b_ref.collection("otpEvents").document(cid), {
            "type": "end",
            "otpHash": hash_code(code),
            "verified": False,
            "generatedAt": now_ts()
        })
        batch.commit()

        return jsonify({"ok": True, "correlationId": cid}), 200
    except Exception as e:
        print(f"Generate End OTP Error: {e}")
        return jsonify({"error": str(e)}), 500

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
        if evt_data.get("verified", False):
            return jsonify({"valid": True, "message": "Already verified"}), 200

        evt_ref.update({"verified": True, "verifiedAt": now_ts()})

        booking = b_ref.get().to_dict()
        worker_id = booking["workerId"]
        cw_name = booking.get("serviceType", "General")

        cw_id = None
        try:
            for doc in db.collection(COL_CW).where("canonicalWork", "==", cw_name).limit(1).stream():
                cw_id = doc.id
                break
        except Exception as e:
            print(f"Error fetching CW ID: {e}")

        now_ts_val = now_ts()

        b_ref.update({
            "status": "e3",
            "completedAt": now_ts_val,
            "updatedAt": now_ts_val,
            "payment.status": "paid" if data.get("paymentReceived") else "pending"
        })

        w_ref = db.collection(COL_WORKERS).document(worker_id)
        w_ref.update({"completedBookings": firestore.Increment(1), "updatedAt": now_ts_val})

        try:
            w_doc = w_ref.get().to_dict()
            skill_map = w_doc.get("cwSkillScore", {})

            if cw_name in skill_map:
                curr_score = skill_map[cw_name].get("score", 0)

                # Boost score slightly, allowing the submit-rating transaction to correct it to an average
                new_score = min(5.0, curr_score + 0.05)

                w_ref.update({
                    f"cwSkillScore.{cw_name}.score": new_score,
                    f"cwSkillScore.{cw_name}.jobsCompleted": firestore.Increment(1)
                })
            else:
                # Initialize the score for a newly completed job type
                w_ref.update({
                    f"cwSkillScore.{cw_name}": {"score": 4.0, "jobsCompleted": 1}
                })

            if cw_id:
                db.collection(COL_CW).document(cw_id).update({"totalJobsGlobal": firestore.Increment(1)})

        except Exception as e:
            print(f"Skill/Global CW update error: {e}")

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
        print(f"Submit Rating Error: {e}")
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

        transaction = db.transaction()
        cancel_booking_in_transaction(transaction, booking_ref, user_id, reason)

        # Cleanup pending requests
        reqs = booking_ref.collection("workerRequests")\
            .where("status", "==", "pending").stream()
        batch = db.batch()
        has_updates = False
        now_ts_val = now_ts()

        for r in reqs:
            batch.update(r.reference, {
                "status": "cancelled_booking",
                "updatedAt": now_ts_val
            })
            has_updates = True

        if has_updates:
            batch.commit()

        return jsonify({"ok": True}), 200
    except Exception as e:
        print(f"Cancel Booking Error: {e}")
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
        print(f"Get Booking Error: {e}")
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
    for i in range(SLOT_COUNT):
        if (current_mask >> i) & 1:
            available_hours.append(i + HOUR_OFFSET)

    return jsonify({"ok": True, "availableHours": available_hours}), 200

@app.route("/expire-requests", methods=["POST"])
@require_secret
def expire_requests():
    data = request.json or {}
    older = int(data.get("olderThanSeconds", 3600))
    cutoff_dt = datetime.now(timezone.utc) - timedelta(seconds=older)
    now_ts_val = now_ts()

    try:
        q = db.collection(COL_BOOKINGS).where("status", "==", "b2").stream()
        updated_count = 0
        batch = db.batch()

        for b in q:
            reqs = b.reference.collection("workerRequests")\
                .where("status", "==", "pending").stream()

            for r in reqs:
                r_data = r.to_dict()
                sent_at = r_data.get("sentAt")

                if isinstance(sent_at, datetime):
                    if sent_at < cutoff_dt.replace(tzinfo=timezone.utc):
                        batch.update(r.reference, {"status": "expired", "updatedAt": now_ts_val})
                        updated_count += 1
                elif sent_at is None:
                    pass

        if updated_count > 0:
             batch.commit()

        return jsonify({"ok": True, "expired": updated_count}), 200
    except Exception as e:
        print(f"Expire Requests Error: {e}")
        return jsonify({"error": str(e)}), 500

# --- HEALTH CHECK ---

@app.route("/", methods=["GET"])
def health_check():
    return jsonify({
        "status": "healthy",
        "service": "Kaarya Unified Backend",
        "version": "3.0-Corrected",
        "features": [
            "AI-powered skill extraction (Hierarchical)",
            "Global Canonical Work Registry (COL_CW)",
            "Verified Worker Onboarding (predict-multi)",
            "Smart worker matching (Hierarchical Vector Fallback)",
            "Vector-based job classification (Pinecone)",
            "Transactional updates",
            "OTP-based job lifecycle"
        ]
    }), 200

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
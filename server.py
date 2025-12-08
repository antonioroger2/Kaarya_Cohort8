import os
import secrets
import hashlib
import uuid
import json
import requests
import re
import time
from datetime import datetime, timedelta, timezone
from functools import wraps
from flask import Flask, request, jsonify
from flask_cors import CORS
import firebase_admin
from firebase_admin import credentials, firestore, auth
# Ensure firestore.ArrayUnion is imported correctly from the client
from firebase_admin.firestore import transactional
from google.cloud.firestore import FieldFilter
from dotenv import load_dotenv

load_dotenv()

# --- CONFIGURATION (Unchanged) ---
API_SECRET = os.environ.get("OTP_API_SECRET", "HiFhGDorJRULc1Z")
FIREBASE_CRED = "firebase-service-account-key.json"
MISSED_CALL_NO = os.environ.get("MISSED_CALL_NO", "1234567890")
EMAIL_SUFFIX = "@kaaryaconnect.app"
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", os.environ.get("HF_API_KEY", ""))
PINECONE_API_KEY = os.environ.get("PINECONE_API_KEY", "")
EMBEDDING_DIMENSION = 1024
PINECONE_MODEL = "llama-text-embed-v2"
GROQ_LLM_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = "llama-3.1-8b-instant"
MAX_LLM_RETRIES = 2
PINECONE_INDEX_HOST = os.environ.get("PINECONE_INDEX_HOST", "https://llama-text-embed-v2-index-cxjha2i.svc.aped-4627-b74a.pinecone.io")
PINECONE_EMBED_URL = "https://api.pinecone.io/embed"
HOUR_OFFSET = 0
SLOT_COUNT = 24
FULL_MASK = (1 << SLOT_COUNT) - 1
headers_llm = {"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"}
headers_pinecone = {
    "Api-Key": PINECONE_API_KEY,
    "Content-Type": "application/json",
    "X-Pinecone-Api-Version": "2025-10"
}

# --- INIT FIREBASE (Unchanged) ---
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate(FIREBASE_CRED)
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"FIREBASE INIT ERROR: {e}")

db = firestore.client()
app = Flask(__name__)
CORS(app)

# --- DB COLLECTION NAMES (Unchanged) ---
COL_USERS = "users"
COL_WORKERS = "workers"
COL_BOOKINGS = "bookings"
COL_CW = "canonical_works"
COL_TOOLS = "tools"
COL_OTP = "otp"
COL_VERIFIED = "verified_signups"
COL_HISTORY = "raw_to_canonical_history"
COL_CATEGORIES = "main_categories"

# --- SMS TEMPLATES (Unchanged) ---
T_JOB_ALERT = ("[{role}] JOB ALERT: Service requested at {locality} on {date}. "
             "Time: {from_time} to {to_time} (approx. {hours} hours) at ₹{wage}. "
             "Notes: {details}. To accept, reply 'ACCEPT' or use the app. Missed call: {missed_call_no} ~ Kaarya")
T_REMINDER = ("30 MINUTE REMINDER: Your [{role}] job at {locality} starts at {from_time} on {date}. "
              "Full Address: {address}. For directions, click: {gmaps} ~ Team Kaarya")
T_START_OTP = ("JOB START OTP: Your code for the {locality} job on {date} ({from_time}-{to_time}) is {otp}. "
              "Total Est: ₹{wage} ({wph}/hr). Share with customer to confirm START.")
T_END_OTP = ("JOB END OTP: Your completion code for the {locality} job on {date} is {otp}. "
              "Elapsed Time: {hours} hours (Final Wage: ₹{wage}). SHARE WITH CUSTOMER to confirm payment received.")

# --- HELPER FUNCTIONS: CORE (Unchanged) ---
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

# --- HELPER FUNCTIONS: AI & VECTOR (Unchanged from corrected version) ---

def run_llm(prompt, max_new_tokens=200):
    if not GROQ_API_KEY: return "LLM_DISABLED"

    payload = {
        "model": GROQ_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False, "max_tokens": max_new_tokens, "temperature": 0.3
    }

    for attempt in range(MAX_LLM_RETRIES + 1):
        try:
            r = requests.post(GROQ_LLM_URL, headers=headers_llm, json=payload, timeout=90)
            if r.status_code == 429:
                delay = 3 * (attempt + 1)
                print(f"Groq LLM API Rate Limit (429). Retrying in {delay}s...")
                time.sleep(delay)
                continue
            if r.status_code != 200:
                print(f"Groq LLM API HTTP Error: {r.status_code}. Body: {r.text[:100]}")
                return "LLM_ERROR"

            return r.json()["choices"][0]["message"]["content"].strip()

        except requests.exceptions.Timeout:
            print("Groq LLM API Timeout.")
            return "LLM_ERROR"
        except Exception as e:
            print(f"Groq LLM Connection Error: {e}")
            return "LLM_ERROR"

    print("Groq LLM API failed after max retries.")
    return "LLM_ERROR"


def pinecone_embed_text(text):
    if not PINECONE_API_KEY: return [0.0] * EMBEDDING_DIMENSION

    url = PINECONE_EMBED_URL
    embed_headers = {
        "Api-Key": PINECONE_API_KEY,
        "Content-Type": "application/json",
        "X-Pinecone-Api-Version": "2025-10"
    }

    payload = {
        "model": PINECONE_MODEL,
        "parameters": {
          "input_type": "passage",
          "truncate": "END"
        },
        "inputs": [{"text": text}]
    }

    try:
        r = requests.post(url, headers=embed_headers, json=payload, timeout=90)
        if r.status_code != 200:
            print(f"Pinecone embed error (Inference API): {r.status_code} {r.text[:100]}")
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
    url = f"{PINECONE_INDEX_HOST}/vectors/upsert"
    payload = {
        "vectors": [{
            "id": vector_id,
            "values": embedding,
            "metadata": metadata
        }]
    }
    try:
        r = requests.post(url, headers=headers_pinecone, json=payload, timeout=90)
        return r.status_code < 400
    except:
        return False

def pinecone_query(embedding, top_k=5, filter_dict=None):
    if not PINECONE_API_KEY: return []
    url = f"{PINECONE_INDEX_HOST}/query"
    payload = {
        "vector": embedding,
        "topK": top_k,
        "includeMetadata": True
    }
    if filter_dict:
        payload["filter"] = filter_dict
    try:
        r = requests.post(url, headers=headers_pinecone, json=payload, timeout=90)
        if r.status_code >= 400: return []
        matches = r.json().get("matches", [])
        return [{
            "id": m.get("id"),
            "score": m.get("score", 0.0),
            "metadata": m.get("metadata", {})
        } for m in matches]
    except:
        return []

# --- LLM STRICT MODE FUNCTIONS (Tool Prompt Corrected, JSON Parsing is the cause of the 'no distinct skills' error) ---

def llm_select_best_match(user_input, candidates):
    candidates_str = ""
    for idx, c in enumerate(candidates):
        meta = c.get('metadata', {})
        name = meta.get('canonicalWork', meta.get('name', 'Unknown'))
        category = meta.get('category', 'N/A')

        candidates_str += f"{idx+1}. ID: {c.get('id')} | Name: {name} | Category: {category}\n"

    prompt = f"""User Request: "{user_input}"
Available Entities (from database):
{candidates_str}
Task: Identify which entity index best matches the user request.
- If one or more matches well, reply ONLY the 1-based index number (e.g., '1', '2', or '3').
- If none match well, return "NONE".
Answer (Index ONLY):"""

    result = run_llm(prompt, max_new_tokens=5)
    result = result.strip().upper()

    if result in ("NONE", "LLM_ERROR", "LLM_DISABLED"):
        return None

    try:
        index = int(result)
        if 1 <= index <= len(candidates):
            return candidates[index - 1].get('id')
    except:
        pass

    return None

def llm_generate_new_entity(user_input, entity_type, existing_context=""):
    if entity_type == "cw":
        prompt = f"""User request: "{user_input}"
Top Match context: {existing_context}
Task: Define a new standard Task. Focus on broad MACRO LEVEL, standard categories and tasks.
1. 'category': Standard, broad Category (e.g., Plumber, Electrician).
2. 'name': Max 2 to 3 words (e.g., 'Tap Installation Repair', 'Fan Installation').
3. 'description': Max 30 words.
Return JSON: {{"category": "...", "name": "...", "description": "..."}}"""
        max_tokens = 100

    elif entity_type == "tool":
        # FIXED: Added strict exclusion rule for robustness
        prompt = f"""User describe : "{user_input}"
Task: For the job description Normalize this input to a MACRO-LEVEL tool name that the job might need. The tool must be a reusable piece of equipment. STRICTLY EXCLUDE brand names, model numbers, and specific products if the input is 'UPS Guard Pro' or 'Bosch Drill', the name must be 'Multimeter' or 'Power Drill').
1. 'name': Standard, MACRO-LEVEL tool name (e.g., 'Screwdriver') 2 to 3 words max.
2. 'description': Brief description of the tool's general purpose (MAX 10 words).
Return JSON: {{"name": "...", "description": "..."}}"""
        max_tokens = 100

    elif entity_type == "category":
        prompt = f"""User defines: "{user_input}"
Task: Define a new Main Category for the user input.
1. 'name': Standard, broad Category name (e.g., Plumbing, Electrical).
2. 'description': Brief description of the category's scope (Max 30 words).
Return JSON: {{"name": "...", "description": "..."}}"""
        max_tokens = 100

    else:
        raise ValueError("Invalid entity_type for generation.")

    response = run_llm(prompt, max_new_tokens=max_tokens)

    if response in ("LLM_DISABLED", "LLM_ERROR"):
        return (None, None, None) if entity_type == "cw" else (None, None)

    try:
        # Robustly extract JSON block
        if "```json" in response:
            response = response.split("```json", 1)[1].rsplit("```", 1)[0].strip()
        elif "```" in response:
            response = response.split("```", 1)[1].rsplit("```", 1)[0].strip()


        match = re.search(r'\{.*?\}', response, re.DOTALL)

        if match:
            clean_json_str = match.group(0)
            data = json.loads(clean_json_str)
        else:
            raise ValueError("No parsable JSON object found.")


        if entity_type == "cw":
            return data.get('category'), data.get('name'), data.get('description')
        elif entity_type in ("tool", "category"):
            return data.get('name'), data.get('description')

    except Exception as e:
        print(f"LLM Parse FATAL Error during {entity_type} generation: {e} | Raw: {response}")
        pass

    return (None, None, None) if entity_type == "cw" else (None, None)

def analyze_worker_profile_hierarchical(description):
    prompt = f"""Analyze the following worker description: "{description}"

    Task: Identify the main-job, macro-level jobs (Category and Task) the worker performs. For EACH job, determine:
    1. Broad Category (e.g. Plumber, Electrician)
    2. Specific Macro-Task (e.g. Tap Repair, Fan Installation). Keep the task name concise.
    3. Required Tools (List of 5-7 essential macro-level tools: e.g., 'Screwdriver Set').

    You must output ONLY a valid JSON list of objects. Do NOT include any introductory text or markdown tags. If no skills are found, return an empty list: [].

    Example Structure:
    [
      {{"category": "Plumber", "task": "Pipe Fixing", "tools": ["Wrench Set", "Sealant"]}},
      {{"category": "Electrician", "task": "Switch Replacement", "tools": ["Screwdriver Set", "Voltage Tester"]}}
    ]

    JSON List:"""

    response = run_llm(prompt, max_new_tokens=1024)

    if response in ("LLM_DISABLED", "LLM_ERROR"):
        print("Analyze Hierarchy Failed: LLM returned generic error state.")
        return []


    try:
        # Handle JSON extraction/cleaning
        if response.startswith('['):
            pass
        elif "```json" in response:
            response = response.split("```json", 1)[1].rsplit("```", 1)[0].strip()
        elif "```" in response:
            response = response.split("```", 1)[1].rsplit("```", 1)[0].strip()

        data = json.loads(response)

        if isinstance(data, list):
            # FIXED LLM FAILURE: If the LLM returns an empty list, it's fine.
            return data
        else:
            print(f"Analyze Hierarchy Failed: JSON loaded successfully but was not a list. Type: {type(data)}")
            return []

    except Exception as e:
        # This catches the JSONDecodeError that causes the 'no distinct skills' error.
        print(f"Analyze Hierarchy Failed: JSON Parse Failure: {e} | Raw Response: {response[:150]}...")
        return []

# --- GLOBAL CANONICAL WORK AND TOOL MANAGEMENT (STRICT FETCH) ---

def get_or_create_main_category(raw_category_name):
    # (Category creation logic remains unchanged)
    raw_category_name = str(raw_category_name).strip().title()

    embedding = pinecone_embed_text(raw_category_name)
    matches = pinecone_query(embedding, top_k=5, filter_dict={"type": "category"})

    selected_cat_id = None

    if matches:
        selected_cat_id = llm_select_best_match(raw_category_name, matches)

    if selected_cat_id:
        doc = db.collection(COL_CATEGORIES).document(selected_cat_id).get().to_dict()
        print(f"✅ Found Existing Category: {doc['name']} ({doc['category_id']})")
        return doc['category_id'], doc['name']

    print(f"🆕 Creating New Category: {raw_category_name}")

    cat_name, cat_desc = llm_generate_new_entity(raw_category_name, "category")

    if not cat_name:
        cat_name = raw_category_name
        cat_desc = f"User defined category: {raw_category_name}"

    cat_id = str(uuid.uuid4())
    embedding = pinecone_embed_text(cat_name)

    firestore_data = {
        "category_id": cat_id,
        "name": cat_name,
        "description": cat_desc,
        "type": "category",
        "createdAt": now_ts()
    }

    pinecone_metadata = {
        "category_id": cat_id,
        "name": cat_name,
        "description": cat_desc,
        "type": "category"
    }

    db.collection(COL_CATEGORIES).document(cat_id).set(firestore_data)
    pinecone_upsert(cat_id, embedding, pinecone_metadata)

    return cat_id, cat_name

def get_or_create_canonical_tool(raw_tool_name):
    raw_tool_name = str(raw_tool_name).strip()
    if len(raw_tool_name) < 2: return None

    # CORRECTION 1: Robust Tool Embedding (Search based on name + context)
    search_input = f"{raw_tool_name}: general repair/installation equipment."

    embedding = pinecone_embed_text(search_input)

    # CORRECTION 2: Set top_k to 8
    matches = pinecone_query(embedding, top_k=8, filter_dict={"type": "tool"})

    selected_tool_id = None

    if matches:
        selected_tool_id = llm_select_best_match(raw_tool_name, matches)

    if selected_tool_id:
        doc = db.collection(COL_TOOLS).document(selected_tool_id).get().to_dict()
        print(f"🔧 Tool Match (LLM Selected): '{raw_tool_name}' -> '{doc['name']}'")
        return doc['name']

    # CORRECTION 3: FALLBACK TO GENERATION ONLY AT EXTREME CASE
    print(f"🆕 Creating New Tool (Extreme Fallback): {raw_tool_name}")
    clean_name, description = llm_generate_new_entity(raw_tool_name, "tool")

    if not clean_name:
        clean_name = raw_tool_name
        description = f"User defined tool: {raw_tool_name}"

    # CORRECTION 4: Update Embedding for the New Tool to include description
    tool_id = slugify(clean_name)
    embedding = pinecone_embed_text(f"{clean_name} {description}")

    existing_doc = db.collection(COL_TOOLS).document(tool_id).get()
    if existing_doc.exists:
        return existing_doc.to_dict()['name']


    firestore_data = {
        "tool_id": tool_id,
        "name": clean_name,
        "description": description,
        "type": "tool",
        "createdAt": now_ts(),
        "usageCount": 1
    }
    pinecone_metadata = {
        "tool_id": tool_id,
        "name": clean_name,
        "type": "tool",
        "description": description
    }

    db.collection(COL_TOOLS).document(tool_id).set(firestore_data)
    pinecone_upsert(tool_id, embedding, pinecone_metadata)

    return clean_name

# *** CRITICAL FIX APPLIED HERE: Added 'provided_tools=None' argument ***
def get_or_create_global_canonical_work(raw_category, raw_task_input, provided_tools=None):


    cat_id, cat_name = get_or_create_main_category(raw_category)


    embedding = pinecone_embed_text(raw_task_input)
    matches = pinecone_query(embedding, top_k=5, filter_dict={"type": "job", "category_id": cat_id})

    selected_cw_id = None

    if matches:
        selected_cw_id = llm_select_best_match(raw_task_input, matches)

        if selected_cw_id:

            return db.collection(COL_CW).document(selected_cw_id).get().to_dict()


    print(f"🆕 Creating New CW: {raw_task_input} under {cat_name}")


    ai_cat, cw_name, cw_desc = llm_generate_new_entity(raw_task_input, "cw")

    if not cw_name:
        cw_name = slugify(raw_task_input)[:32]
        cw_desc = f"AI Generation Failed. Manual description for {cw_name}."

    cw_id = str(uuid.uuid4())
    embedding = pinecone_embed_text(f"{cat_name} {cw_name}")

    final_tool_names = []
    target_tool_list = provided_tools if provided_tools else []

    if not target_tool_list:
        concepts_prompt = f"List exactly 5 essential tool names for '{cw_name}'. Respond only with the tool names, comma-separated. Use macro-level names only (e.g., 'Screwdriver Set', 'Wrench Set'). Do not include descriptions or extra text."
        concepts_str = run_llm(concepts_prompt, max_new_tokens=100)
        target_tool_list = [t.strip() for t in concepts_str.split(',') if t.strip()]
    for t_name in target_tool_list:
        canonical_name = get_or_create_canonical_tool(t_name)
        if canonical_name:
            final_tool_names.append(canonical_name)


    firestore_data = {
        "cw_id": cw_id,
        "canonicalWork": cw_name,
        "description": cw_desc,
        "category_id": cat_id,
        "category": cat_name,
        "requiredTools": list(set(final_tool_names)),
        "createdAt": now_ts(),
        "totalJobsGlobal": 0
    }

    pinecone_metadata = {
        "cw_id": cw_id,
        "canonicalWork": cw_name,
        "category_id": cat_id,
        "category": cat_name,
        "description": cw_desc,
        "type": "job"
    }

    db.collection(COL_CW).document(cw_id).set(firestore_data)
    pinecone_upsert(cw_id, embedding, pinecone_metadata)

    ret_data = firestore_data.copy()
    ret_data["createdAt"] = datetime.now(timezone.utc).isoformat()
    return ret_data

# --- SMART WORKER MATCHING (Unchanged) ---
def calculate_worker_score(worker, cw_name, required_tools):
    # ... (function body omitted, assumed correct)
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

    tool_score = tool_match_ratio * 5.0

    final_score = (cw_score * 0.6) + (global_rating * 0.2) + (tool_score * 0.2)

    return {
        "finalScore": final_score,
        "cwScore": cw_score,
        "toolScore": tool_score,
        "globalRating": global_rating
    }

def get_best_workers_for_job(cw_name, cw_category, required_tools, top_k=5):
    # ... (function body omitted, assumed correct)
    """
    Smart worker matching using Firestore query and local scoring, with fallback.
    """
    candidates = []


    try:
        docs = db.collection(COL_WORKERS)\
            .where(filter=FieldFilter("canonicalWorks", "array_contains", cw_name))\
            .where(filter=FieldFilter("isActive", "==", True))\
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
            if len(candidates) >= top_k:
                 return candidates[:top_k]

    except Exception as e:
        print(f"Error during CW exact match query: {e}")


    if cw_category and cw_category != "General":
        try:
            all_docs = db.collection(COL_WORKERS).where(filter=FieldFilter("isActive", "==", True)).limit(200).stream()

            for doc in all_docs:
                w = doc.to_dict()

                if any(c["workerId"] == doc.id for c in candidates):
                    continue

                if cw_category in w.get("cw_data", {}):
                    cat_scores = [float(x.get("rating", 0.0)) for x in w["cw_data"][cw_category].values()]
                    baseline = max(cat_scores) if cat_scores else 4.0

                    w_sim = w.copy()
                    w_sim["cwSkillScore"] = {cw_name: {"score": baseline}}

                    score = calculate_worker_score(w_sim, cw_name, required_tools)

                    candidates.append({
                        "workerId": doc.id,
                        "score": score["finalScore"] * 0.95,
                        "name": w.get("name"),
                        "phone": w.get("phone"),
                        "breakdown": score
                    })

        except Exception as e:
            print(f"Error during Category fallback query: {e}")


    candidates.sort(key=lambda x: x["score"], reverse=True)
    return candidates[:top_k]

# --- TRANSACTIONAL HELPERS (Unchanged) ---
# ... (cancel_booking_in_transaction, accept_booking_in_transaction, submit_rating_in_transaction omitted)
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

    curr = int(asnap.to_dict().get("mask", FULL_MASK)) if asnap.exists else FULL_MASK
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


    if cw_name in worker_data.get("cwSkillScore", {}):
        task_count = worker_data["cwSkillScore"][cw_name].get("jobsCompleted", 0)
        curr_task_rating = worker_data["cwSkillScore"][cw_name].get("score", 0.0)

        if task_count > 0:
            if task_count == 1:
                new_task_avg = rating
            else:
                old_task_total = curr_task_rating * (task_count - 1)
                new_task_avg = (old_task_total + rating) / task_count

            tx.update(worker_ref, {f"cwSkillScore.{cw_name}.score": new_task_avg})


    tx.update(booking_ref, {
        "rating": rating,
        "review": review,
        "status": "r1",
        "updatedAt": now_ts_val
    })
    return True

# --- ROUTES: AUTH & ONBOARDING (Unchanged) ---
def _handle_auth_creation(uid, password, name):
    try:
        auth.create_user(
            uid=uid,
            email=f"{uid}{EMAIL_SUFFIX}",
            password=password,
            display_name=name
        )
        return True, None
    except auth.EmailAlreadyExistsError:
        return True, None
    except Exception as e:
        return False, str(e)


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

    try:
        data = request.json
        phone = sanitize_phone(data.get("phone"))
        password = data.get("password")
        name = data.get("name")
        is_worker = data.get("isWorker", False)


        uid = phone
        coll = COL_WORKERS if is_worker else COL_USERS
        doc_ref = db.collection(coll).document(uid)
        worker_exists = doc_ref.get().exists


        try:
            hourly = int(data.get("hourlyRate", 300))
        except (ValueError, TypeError):
            hourly = 300


        if not worker_exists:
            if not db.collection(COL_VERIFIED).document(phone).get().exists:
                return jsonify({"error": "Verification required for new signup"}), 403

            if not password:
                return jsonify({"error": "Password required for initial signup"}), 400


            auth_ok, auth_err = _handle_auth_creation(uid, password, name)
            if not auth_ok:
                print(f"Firebase Auth Error: {auth_err}")
                return jsonify({"error": f"Firebase Auth Error: {auth_err}"}), 500

            db.collection(COL_VERIFIED).document(phone).delete()


            base_profile_updates = {
                "uid": uid,
                "phone": phone,
                "name": name,
                "pincode": data.get("pin"),
                "locality": data.get("locality"),
                "role": "worker" if is_worker else "user",
                "createdAt": now_ts(),
                "isActive": True,
                "updatedAt": now_ts()
            }

            if not is_worker:

                doc_ref.set(base_profile_updates, merge=True)
                return jsonify({"ok": True, "uid": uid, "status": "User Created"}), 200

        else:

            if not is_worker:

                update_data = {
                    "name": name,
                    "pincode": data.get("pin"),
                    "locality": data.get("locality"),
                    "updatedAt": now_ts()
                }
                doc_ref.update(update_data)
                return jsonify({"ok": True, "uid": uid, "status": "User Profile Updated"}), 200



        verified_skills_payload = data.get("verifiedSkills", [])

        all_canonical_tools = set()
        cw_data_to_save = {}
        cw_skill_score = {}
        all_canonical_works = []
        tool_normalization_cache = {}


        for skill_entry in verified_skills_payload:
            raw_tools_for_skill = skill_entry.get("myTools", [])
            for raw_tool_str in raw_tools_for_skill:
                raw_tool_str = str(raw_tool_str).strip()
                if raw_tool_str and raw_tool_str not in tool_normalization_cache:
                    canonical_name = get_or_create_canonical_tool(raw_tool_str)
                    if canonical_name:
                        tool_normalization_cache[raw_tool_str] = canonical_name
                        all_canonical_tools.add(canonical_name)


        for skill_entry in verified_skills_payload:
            task = skill_entry.get("task", "General Task").strip()
            category = skill_entry.get("category", "General").strip()
            raw_tools_for_task = skill_entry.get("myTools", [])

            # Note: No 'provided_tools' argument is passed here,
            # as this route infers tools from the loop above and sends an empty list to CW logic.
            cw_doc_data = get_or_create_global_canonical_work(category, task)

            task_name_std = cw_doc_data['canonicalWork']
            category_name_std = cw_doc_data['category']

            all_canonical_works.append(task_name_std)
            task_slug = slugify(task_name_std)

            canonical_tools_for_task = [
                tool_normalization_cache[str(t).strip()]
                for t in raw_tools_for_task
                if str(t).strip() in tool_normalization_cache
            ]

            if category_name_std not in cw_data_to_save:
                cw_data_to_save[category_name_std] = {}

            cw_data_to_save[category_name_std][task_slug] = {
                "name": task_name_std,
                "category": category_name_std,
                "tools": list(set(canonical_tools_for_task)),
                "rating": 5.0,
                "total_works": 0
            }

            if task_name_std not in cw_skill_score:
                cw_skill_score[task_name_std] = {"score": 5.0, "jobsCompleted": 0}


        worker_update_data = {
            "name": name,
            "pincode": data.get("pin"),
            "locality": data.get("locality"),
            "perHourCharge": hourly,
            "toolsAvailable": list(all_canonical_tools),
            "canonicalWorks": list(set(all_canonical_works)),
            "cwSkillScore": cw_skill_score,
            "cw_data": cw_data_to_save,
            "profileDescription": data.get("profileDescription"),
            "updatedAt": now_ts(),
        }

        if not worker_exists:

            worker_update_data.update({
                "avgRating": 5.0,
                "completedBookings": 0,
                "availability": "Y",
                **base_profile_updates,
            })
            doc_ref.set(worker_update_data, merge=True)
            return jsonify({"ok": True, "uid": uid, "status": "Worker Created & Profile Set"}), 200
        else:

            doc_ref.update(worker_update_data)
            return jsonify({"ok": True, "uid": uid, "status": "Worker Profile Updated"}), 200


    except Exception as e:
        print(f"Signup/Update Error for {uid}: {e}")
        return jsonify({"error": str(e)}), 500

# --- ROUTES: BOOKING & TRANSACTIONS (Remaining endpoints) ---

@app.route("/cw/predict-multi", methods=["POST"])
@require_secret
def predict_multi_skills():
    data = request.json
    text = data.get("text")

    if not text:
        return jsonify({"error": "text required"}), 400

    # Handles the 'Analysis Error: Exception: Al found no distinct skills' by returning [] on parse failure
    ai_jobs = analyze_worker_profile_hierarchical(text)

    results = []
    seen = set()

    for job in ai_jobs:
        cat = job.get("category")
        task = job.get("task")
        raw_tools = job.get("tools", []) # Extracted raw tool names

        if not cat or not task: continue

        key = f"{cat}_{task}"
        if key in seen: continue
        seen.add(key)

        try:
            # FIX APPLIED: Passing raw_tools to the newly updated function signature
            global_cw = get_or_create_global_canonical_work(cat, task, provided_tools=raw_tools)
        except Exception as e:
            # This should no longer occur with the signature fix
            print(f"Error fetching/creating CW: {e}")
            continue

        results.append({
            "category": global_cw['category'],
            "task": global_cw['canonicalWork'],
            "cw_id": global_cw["cw_id"],
            "suggestedTools": global_cw["requiredTools"],
            "aiSuggestedToolsFromProfile": global_cw["requiredTools"]
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

        matches = pinecone_query(embedding, top_k=3, filter_dict={"type": "job"})

        selected_cw_data = None
        selected_cw_id = None

        if matches:

            selected_cw_id = llm_select_best_match(text, matches)

            if selected_cw_id:

                selected_cw_data = db.collection(COL_CW).document(selected_cw_id).get().to_dict()

        if selected_cw_data:

            return jsonify({
                "canonicalWork": selected_cw_data.get("canonicalWork"),
                "requiredTools": selected_cw_data.get("requiredTools", []),
                "confidence": next((m['score'] for m in matches if m['id'] == selected_cw_id), 0.0),
                "isNew": False,
                "alternatives": [m["metadata"] for m in matches if m['id'] != selected_cw_id]
            }), 200
        else:

            print(f"COLD START: Generating new CW for notes: {text}")

            category, cw_name, description = llm_generate_new_entity(text, "cw")

            if not cw_name:
                return jsonify({"error": "AI failed to categorize the request."}), 400

            # This call uses the internal LLM fallback for tools since provided_tools=None
            global_cw = get_or_create_global_canonical_work(category, cw_name)

            return jsonify({
                "canonicalWork": global_cw["canonicalWork"],
                "requiredTools": global_cw["requiredTools"],
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

        if "LLM_ERROR" in normalized or "LLM_DISABLED" in normalized:
             return jsonify({"error": "Tool normalization failed or disabled."}), 500

        return jsonify({"original": tool_input, "normalized": normalized}), 200
    except Exception as e:
        print(f"Normalize Tool Error: {e}")
        return jsonify({"error": str(e)}), 500



@app.route("/create-booking", methods=["POST"])
@require_secret
def create_booking():
    data = request.json
    user_id = data.get("userId")
    candidate_workers_input = data.get("candidateWorkers", [])


    notes = data.get("notes", "")
    service_type = data.get("serviceType", "General").strip()
    service_category = data.get("serviceCategory", "General").strip()
    required_tools = data.get("requiredTools", []) or []

    if not candidate_workers_input:
        if len(notes) < 20:
            return jsonify({"error": "Job description too short. Requires a minimum of 20 characters for accurate matching."}), 400


        embedding = pinecone_embed_text(notes)
        matches = pinecone_query(embedding, top_k=3, filter_dict={"type": "job"})

        selected_cw_data = None
        selected_cw_id = None

        if matches:
            selected_cw_id = llm_select_best_match(notes, matches)
            if selected_cw_id:
                selected_cw_data = db.collection(COL_CW).document(selected_cw_id).get().to_dict()

        if selected_cw_data:
            cw_data = selected_cw_data
        else:

            category, cw_name, description = llm_generate_new_entity(notes, "cw")

            if not cw_name:
                return jsonify({"error": "AI failed to categorize job request for matching."}), 400

            # This call uses the internal LLM fallback for tools since provided_tools=None
            cw_data = get_or_create_global_canonical_work(category, cw_name)


        service_type = cw_data["canonicalWork"]
        service_category = cw_data["category"]
        required_tools = cw_data["requiredTools"]

        data["serviceType"] = service_type
        data["serviceCategory"] = service_category
        data["requiredTools"] = required_tools


    final_candidates = candidate_workers_input
    if not final_candidates:
        best_workers = get_best_workers_for_job(service_type, service_category, required_tools, top_k=5)
        final_candidates = [w["workerId"] for w in best_workers]
        data["candidateWorkersDetails"] = best_workers

    if not final_candidates:
        return jsonify({"error": f"No workers found for Canonical Work: {service_type} in category: {service_category}. Try simplifying your description or checking worker profiles."}), 404


    try:
        date_str = data["date"]
        start_hour = int(data["startHour"])
        end_hour = int(data["endHour"])
        wage = int(data["wage"])
        hours = end_hour - start_hour

        dt_obj = datetime.strptime(date_str, "%Y-%m-%d")
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

        batch.update(booking_ref, {"status": "b2"})
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
        return jsonify({"ok": True, "message": "1 user request processed"}), 200
    except Exception as e:
        error_msg = str(e)
        print(f"Worker Accept Error: {error_msg}")

        if "WORKER_NOT_AVAILABLE" in error_msg:
            return jsonify({
                "ok": False,
                "error": f"Worker {wid} not available for given time try later",
                "message": "0 user requests processed"
            }), 400

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
            for doc in db.collection(COL_CW).where(filter=FieldFilter("canonicalWork", "==", cw_name)).limit(1).stream():
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


                new_score = min(5.0, curr_score + 0.05)

                w_ref.update({
                    f"cwSkillScore.{cw_name}.score": new_score,
                    f"cwSkillScore.{cw_name}.jobsCompleted": firestore.Increment(1)
                })
            else:

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


        reqs = booking_ref.collection("workerRequests")\
            .where(filter=FieldFilter("status", "==", "pending")).stream()
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
        q = db.collection(COL_BOOKINGS).where(filter=FieldFilter("status", "==", "b2")).stream()
        updated_count = 0
        batch = db.batch()

        for b in q:
            reqs = b.reference.collection("workerRequests")\
                .where(filter=FieldFilter("status", "==", "pending")).stream()

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



@app.route("/", methods=["GET"])
def health_check():
    return jsonify({
        "status": "healthy"
    }), 200

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
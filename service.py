############################################################
#   CANONICAL WORK - TOOL NORMALISER BACKEND API 
############################################################

from flask import Flask, request, jsonify
import json
import os
import math
from datetime import datetime
import requests

app = Flask(__name__)

DATA_DIR = "cws_data"

def load(file):
    path = os.path.join(DATA_DIR, file)
    if not os.path.exists(path):
        return []
    with open(path, "r") as f:
        return json.load(f)

def save(file, data):
    path = os.path.join(DATA_DIR, file)
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

HF_API_KEY = "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"   
HF_EMB_URL = "https://router.huggingface.co/hf-inference/models/BAAI/bge-large-en-v1.5/pipeline/feature-extraction"
HF_LLM_URL = "https://router.huggingface.co/v1/chat/completions"

headers_emb = {
    "Authorization": f"Bearer {HF_API_KEY}",
    "Content-Type": "application/json"
}

headers_llm = {
    "Authorization": f"Bearer {HF_API_KEY}",
    "Content-Type": "application/json"
}

headers_llm = {
    "Authorization": f"Bearer {HF_API_KEY}",
    "Content-Type": "application/json"
}

PINECONE_API_KEY = "pcsk_2rWNz3_R4Xj1roK7EYXmwwPwxLXm8ix2TcscAXnujuZBccfo5nXjsWEeqegYnSSxc82N3E"
PINECONE_HOST = "https://llama-text-embed-v2-index-0s8x0bx.svc.aped-4627-b74a.pinecone.io"

headers_pinecone = {
    "Api-Key": PINECONE_API_KEY,
    "Content-Type": "application/json"
}

def generate_embedding(text):
    payload = {
        "inputs": text
    }

    r = requests.post(HF_EMB_URL, headers=headers_emb, json=payload)

    if r.status_code != 200:
        raise RuntimeError(f"HF embedding failed: {r.status_code} {r.text}")

    out = r.json()

    # Case 1: HF returned a flat vector (your case)
    if isinstance(out, list) and all(isinstance(x, float) for x in out):
        return out

    # Case 2: HF returned nested [[vec]]
    if isinstance(out, list) and len(out) == 1 and isinstance(out[0], list):
        return out[0]

    # Case 3: dict-based responses (other HF routers)
    if isinstance(out, dict):
        if "embeddings" in out:
            return out["embeddings"][0]
        if "outputs" in out:
            return out["outputs"][0]
        if "data" in out and "embedding" in out["data"][0]:
            return out["data"][0]["embedding"]

    raise RuntimeError(f"Unknown HF embedding format: {out}")


def run_llm(prompt, max_new_tokens=200):
    payload = {
    "model": "mistralai/Mistral-7B-Instruct-v0.2:featherless-ai",
    "messages": [
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "max_tokens": 200
}

    r = requests.post(HF_LLM_URL, headers=headers_llm, json=payload)

    if r.status_code != 200:
        raise RuntimeError(f"HF LLM Error: {r.status_code} {r.text}")

    data = r.json()
    return data["choices"][0]["message"]["content"]

def cosine(v1, v2):
    dot = sum(a * b for a, b in zip(v1, v2))
    mag1 = math.sqrt(sum(a * a for a in v1))
    mag2 = math.sqrt(sum(b * b for b in v2))
    if mag1 == 0 or mag2 == 0:
        return 0.0
    return dot / (mag1 * mag2)

def slugify(text):
    return "".join(c.lower() if c.isalnum() else "" for c in text).strip("")

def pinecone_upsert_cw(cw_id, embedding, metadata):
    url = f"{PINECONE_HOST}/vectors/upsert"
    payload = {
        "vectors": [
            {
                "id": cw_id,
                "values": embedding,
                "metadata": metadata
            }
        ]
    }
    r = requests.post(url, headers=headers_pinecone, json=payload)
    if r.status_code >= 400:
        raise RuntimeError(f"Pinecone upsert error: {r.status_code} {r.text}")

def pinecone_query_cw(embedding, top_k=3, job=None):
    url = f"{PINECONE_HOST}/query"
    payload = {
        "vector": embedding,
        "topK": top_k,
        "includeMetadata": True
    }
    if job:
        payload["filter"] = {"job": {"$eq": job}}
    r = requests.post(url, headers=headers_pinecone, json=payload)
    if r.status_code >= 400:
        return []
    data = r.json()
    matches = data.get("matches", []) or []
    results = []
    for m in matches:
        md = m.get("metadata", {}) or {}
        results.append({
            "id": m.get("id"),
            "score": m.get("score", 0.0),
            "canonicalWork": md.get("canonicalWork"),
            "job": md.get("job"),
            "description": md.get("description"),
            "requiredTools": md.get("requiredTools", [])
        })
    results.sort(key=lambda x: x["score"], reverse=True)
    return results

def extract_entities(text):
    t = text.lower()
    devices = ["tap", "pipe", "flush", "tank", "faucet", "shower", "toilet", "fan", "geyser", "ac", "switchboard", "curtain rod"]
    issues = ["leak", "leaking", "broken", "jammed", "loose", "blocked", "crack", "not working", "no power", "noise"]
    rooms = ["kitchen", "bathroom", "hall", "wash", "bedroom"]
    d_found = [d for d in devices if d in t]
    i_found = [i for i in issues if i in t]
    r_found = [r for r in rooms if r in t]
    return {
        "devices": list(set(d_found)),
        "issues": list(set(i_found)),
        "rooms": list(set(r_found))
    }

def llm_select_cw(user_input, candidates, entities):
    prompt = f"""You are an expert home repair job classifier.

User said: "{user_input}"
Extracted entities: {entities}

Top semantic matches:
{candidates}

Choose the SINGLE most correct canonical work.
If none match, reply exactly: NEW_CW
Do NOT add extra text."""
    out = run_llm(prompt, max_new_tokens=32).strip()
    if "\n" in out:
        out = out.split("\n")[0].strip()
    return out

def llm_generate_new_cw_name(user_input, entities):
    prompt = f"""User description: "{user_input}"
Entities: {entities}

Create a clean, short, standardized job name (canonical work title) for this task 3 Words Max.
Examples: "Tap Fix", "Pipe Leak Fix", "Fan Installation", "Geyser Service", "AC Gas Refill", "Switchboard Repair", "Curtain Rod Fitting".

Return only the job name, nothing else."""
    out = run_llm(prompt, max_new_tokens=32).strip()
    if "\n" in out:
        out = out.split("\n")[0].strip()
    return out

def get_cw_list():
    cw_list = load("canonicalWork.json")
    if not isinstance(cw_list, list):
        cw_list = []
    return cw_list

def save_cw_list(cw_list):
    save("canonicalWork.json", cw_list)

def find_cw_by_name(name):
    cw_list = get_cw_list()
    for cw in cw_list:
        if cw.get("canonicalWork") == name:
            return cw
    return None

def add_or_update_cw_local(job, canonical_work, description, required_tools, embedding=None):
    cw_list = get_cw_list()
    now = datetime.now().isoformat()
    existing = None
    for idx, cw in enumerate(cw_list):
        if cw.get("canonicalWork") == canonical_work:
            existing = idx
            break
    if existing is not None:
        cw = cw_list[existing]
        cw["job"] = job
        cw["canonicalWork"] = canonical_work
        cw["description"] = description
        cw["requiredTools"] = required_tools
        if embedding is not None:
            cw["embedding"] = embedding
        if "jobsCompleted" not in cw:
            cw["jobsCompleted"] = 0
        if "totalScore" not in cw:
            cw["totalScore"] = 0.0
        if "cwScore" not in cw:
            cw["cwScore"] = 0.0
        cw_list[existing] = cw
        cw_id = cw.get("id", f"{job}_{slugify(canonical_work)}")
        cw["id"] = cw_id
    else:
        cw_id = f"{job}_{slugify(canonical_work)}"
        cw = {
            "id": cw_id,
            "job": job,
            "canonicalWork": canonical_work,
            "description": description,
            "requiredTools": required_tools,
            "createdAt": now,
            "jobsCompleted": 0,
            "totalScore": 0.0,
            "cwScore": 0.0
        }
        if embedding is not None:
            cw["embedding"] = embedding
        cw_list.append(cw)
    save_cw_list(cw_list)
    return cw

def update_cw_score(canonical_work_name, rating, difficulty, reliability=1.0):
    cw_list = get_cw_list()
    updated = False
    for cw in cw_list:
        if cw.get("canonicalWork") == canonical_work_name:
            jobs_completed = cw.get("jobsCompleted", 0)
            total_score = cw.get("totalScore", 0.0)
            weight = max(0.1, float(difficulty)) * float(reliability)
            inc = float(rating) * weight
            jobs_completed += 1
            total_score += inc
            cw["jobsCompleted"] = jobs_completed
            cw["totalScore"] = total_score
            cw["cwScore"] = total_score / jobs_completed if jobs_completed > 0 else 0.0
            updated = True
            break
    if updated:
        save_cw_list(cw_list)
    return updated

def get_workers_list():
    workers = load("workerSkillMap.json")
    if not isinstance(workers, list):
        workers = []
    return workers

def save_workers_list(workers):
    save("workerSkillMap.json", workers)

def update_worker_skill(worker_id, canonical_work_name, rating, difficulty, reliability=1.0):
    workers = get_workers_list()
    updated = False
    for w in workers:
        if str(w.get("workerId")) == str(worker_id):
            cw_skill = w.get("cwSkillScore", {})
            entry = cw_skill.get(canonical_work_name, {"jobsCompleted": 0, "totalScore": 0.0, "score": 0.0})
            jobs_completed = entry.get("jobsCompleted", 0)
            total_score = entry.get("totalScore", 0.0)
            weight = max(0.1, float(difficulty)) * float(reliability)
            inc = float(rating) * weight
            jobs_completed += 1
            total_score += inc
            entry["jobsCompleted"] = jobs_completed
            entry["totalScore"] = total_score
            entry["score"] = total_score / jobs_completed if jobs_completed > 0 else 0.0
            cw_skill[canonical_work_name] = entry
            w["cwSkillScore"] = cw_skill
            scores = [e.get("score", 0.0) for e in cw_skill.values()]
            if scores:
                w["skillScore"] = sum(scores) / len(scores)
            if canonical_work_name not in w.get("canonicalWorks", []):
                w.setdefault("canonicalWorks", []).append(canonical_work_name)
            updated = True
            break
    if updated:
        save_workers_list(workers)
    return updated

def semantic_search(query_vec, top_k=3, job=None):
    try:
        results = pinecone_query_cw(query_vec, top_k=top_k, job=job)
        if results:
            return results
    except Exception:
        pass
    cw_list = get_cw_list()
    scored = []
    for cw in cw_list:
        emb = cw.get("embedding")
        if not emb:
            continue
        score = cosine(query_vec, emb)
        scored.append({
            "id": cw.get("id"),
            "canonicalWork": cw.get("canonicalWork"),
            "score": score,
            "job": cw.get("job"),
            "description": cw.get("description"),
            "requiredTools": cw.get("requiredTools", [])
        })
    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored[:top_k]

def match_worker(cw, workers):
    best = None
    best_score = -999999.0
    required_tools = set(cw.get("requiredTools", []))
    cw_name = cw.get("canonicalWork")
    for w in workers:
        tools_available = set(w.get("toolsAvailable", []))
        tools_overlap = len(required_tools & tools_available)
        cw_skill_score = 0.0
        cw_skill_map = w.get("cwSkillScore", {})
        if isinstance(cw_skill_map, dict):
            entry = cw_skill_map.get(cw_name)
            if isinstance(entry, dict):
                cw_skill_score = entry.get("score", 0.0)
        global_skill = float(w.get("skillScore", 0.0))
        score = tools_overlap * 2.0 + cw_skill_score + 0.5 * global_skill
        if score > best_score:
            best_score = score
            best = w
    return best

def explain_match(cw, worker):
    prompt = f"""Explain why this worker is best for the job.

canonicalWork: {cw}
worker: {worker}

Explain in simple language."""
    return run_llm(prompt)

@app.route("/")
def home():
    return {"message": "CWS using HF + Pinecone REST working"}

@app.route("/cw/add", methods=["POST"])
def add_cw():
    data = request.json
    job = data.get("job", "general")
    canonical_work = data["canonicalWork"]
    description = data.get("description", canonical_work)
    required_tools = data.get("requiredTools", [])
    emb = generate_embedding(canonical_work)
    cw = add_or_update_cw_local(job, canonical_work, description, required_tools, emb)
    metadata = {
        "canonicalWork": cw["canonicalWork"],
        "job": cw["job"],
        "description": cw["description"],
        "requiredTools": cw.get("requiredTools", [])
    }
    pinecone_upsert_cw(cw["id"], emb, metadata)
    return {"message": "CW added or updated", "cw": cw}, 201

@app.route("/cw/all", methods=["GET"])
def cw_all():
    return jsonify(get_cw_list())

@app.route("/cw/match", methods=["POST"])
def cw_match():
    body = request.json
    text = body["text"]
    job = body.get("job")
    emb = generate_embedding(text)
    result = semantic_search(emb, top_k=3, job=job)
    return jsonify(result)

@app.route("/cw/predict", methods=["POST"])
def cw_predict():
    body = request.json
    text = body["text"]
    job_hint = body.get("job")
    emb = generate_embedding(text)
    top_matches = semantic_search(emb, top_k=3, job=job_hint)
    candidates = [t["canonicalWork"] for t in top_matches if t.get("canonicalWork")]
    entities = extract_entities(text)
    if candidates:
        final = llm_select_cw(text, candidates, entities)
    else:
        final = "NEW_CW"
    created_new = False
    final_job = job_hint if job_hint else (top_matches[0]["job"] if top_matches else "general")
    final_cw_name = final
    if final == "NEW_CW" or not final:
        final_cw_name = llm_generate_new_cw_name(text, entities)
        existing = find_cw_by_name(final_cw_name)
        if not existing:
            cw = add_or_update_cw_local(final_job, final_cw_name, text, [], emb)
            metadata = {
                "canonicalWork": cw["canonicalWork"],
                "job": cw["job"],
                "description": cw["description"],
                "requiredTools": cw.get("requiredTools", [])
            }
            pinecone_upsert_cw(cw["id"], emb, metadata)
            created_new = True
    else:
        existing = find_cw_by_name(final_cw_name)
        if not existing:
            cw = add_or_update_cw_local(final_job, final_cw_name, text, [], emb)
            metadata = {
                "canonicalWork": cw["canonicalWork"],
                "job": cw["job"],
                "description": cw["description"],
                "requiredTools": cw.get("requiredTools", [])
            }
            pinecone_upsert_cw(cw["id"], emb, metadata)
            created_new = True
    history_entry = {
        "rawInput": text,
        "canonicalWork": final_cw_name,
        "job": final_job,
        "createdAt": datetime.now().isoformat(),
        "source": "cw_predict"
    }
    h = load("rawToCanonicalHistory.json")
    if not isinstance(h, list):
        h = []
    h.append(history_entry)
    save("rawToCanonicalHistory.json", h)
    return {
        "input": text,
        "job_hint": job_hint,
        "top_matches": top_matches,
        "entities": entities,
        "final_canonical_work": final_cw_name,
        "created_new_canonical_work": created_new
    }

@app.route("/workers/add", methods=["POST"])
def add_worker():
    data = request.json
    workers = get_workers_list()
    worker_id = str(data["workerId"])
    existing = None
    for idx, w in enumerate(workers):
        if str(w.get("workerId")) == worker_id:
            existing = idx
            break
    worker = {
        "workerId": worker_id,
        "name": data.get("name", f"Worker {worker_id}"),
        "job": data.get("job", "general"),
        "toolsAvailable": data.get("toolsAvailable", []),
        "skillScore": float(data.get("skillScore", 0.0)),
        "canonicalWorks": data.get("canonicalWorks", []),
        "cwSkillScore": data.get("cwSkillScore", {}),
        "experienceYears": float(data.get("experienceYears", 0.0)),
        "ratingOverall": float(data.get("ratingOverall", 0.0))
    }
    if existing is not None:
        workers[existing] = worker
    else:
        workers.append(worker)
    save_workers_list(workers)
    return {"message": "Worker added or updated"}, 201

@app.route("/workers/all", methods=["GET"])
def workers_all():
    return jsonify(get_workers_list())

@app.route("/cw/recommend-worker", methods=["POST"])
def recommend_worker():
    cw_name = request.json["canonicalWork"]
    cw = find_cw_by_name(cw_name)
    if not cw:
        return {"error": "canonicalWork not found"}, 404
    workers = get_workers_list()
    if not workers:
        return {"error": "no workers available"}, 404
    best = match_worker(cw, workers)
    if not best:
        return {"error": "no suitable worker found"}, 404
    return jsonify(best)

@app.route("/cw/explain", methods=["POST"])
def explain():
    cw = request.json["cw"]
    worker = request.json["worker"]
    return {"explanation": explain_match(cw, worker)}

@app.route("/tools/add", methods=["POST"])
def add_tool():
    data = request.json
    tools = load("toolsDatabase.json")
    if not isinstance(tools, list):
        tools = []
    tools.append(data)
    save("toolsDatabase.json", tools)
    return {"message": "Tool added"}, 201

@app.route("/tools/all", methods=["GET"])
def get_tools():
    return jsonify(load("toolsDatabase.json"))

@app.route("/history/add", methods=["POST"])
def add_history():
    data = request.json
    data["createdAt"] = datetime.now().isoformat()
    h = load("rawToCanonicalHistory.json")
    if not isinstance(h, list):
        h = []
    h.append(data)
    save("rawToCanonicalHistory.json", h)
    return {"message": "History logged"}, 201

@app.route("/history/all", methods=["GET"])
def show_history():
    return jsonify(load("rawToCanonicalHistory.json"))

@app.route("/job/complete", methods=["POST"])
def job_complete():
    data = request.json
    canonical_work_name = data["canonicalWork"]
    worker_id = data["workerId"]
    rating = float(data.get("rating", 5))
    difficulty = float(data.get("difficulty", 1))
    reliability = float(data.get("reliability", 1.0))
    comments = data.get("comments", "")
    update_cw_score(canonical_work_name, rating, difficulty, reliability)
    update_worker_skill(worker_id, canonical_work_name, rating, difficulty, reliability)
    entry = {
        "canonicalWork": canonical_work_name,
        "workerId": worker_id,
        "rating": rating,
        "difficulty": difficulty,
        "reliability": reliability,
        "comments": comments,
        "createdAt": datetime.now().isoformat(),
        "source": "job_complete"
    }
    h = load("rawToCanonicalHistory.json")
    if not isinstance(h, list):
        h = []
    h.append(entry)
    save("rawToCanonicalHistory.json", h)
    return {"message": "Job recorded and scores updated"}, 201

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
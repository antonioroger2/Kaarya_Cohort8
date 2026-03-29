# worker_matching.py
from .firebase_init import db
from .constants import COL_WORKERS
from google.cloud.firestore import FieldFilter

# --- SMART WORKER MATCHING ---
def calculate_worker_score(worker, cw_name, required_tools):
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

def get_best_workers_for_job(cw_name, cw_category, required_tools, top_k=10):
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
                    score = calculate_worker_score(w, cw_name, required_tools)
                    candidates.append({
                        "workerId": doc.id,
                        "score": score["finalScore"],
                        "name": w.get("name"),
                        "phone": w.get("phone"),
                        "breakdown": score
                    })

        except Exception as e:
            print(f"Error during Category fallback query: {e}")

    candidates.sort(key=lambda x: x["score"], reverse=True)
    return candidates[:top_k]
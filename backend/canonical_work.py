# canonical_work.py
import uuid
from datetime import datetime, timezone
from .firebase_init import db
from .constants import COL_CATEGORIES, COL_TOOLS, COL_CW
from .ai_utils import pinecone_embed_text, pinecone_query, pinecone_upsert, run_llm
from .llm_functions import llm_select_best_match, llm_generate_new_entity
from .utils import slugify, now_ts

_category_cache: dict[str, tuple[str, str]] = {}
_tool_name_cache: dict[str, str] = {}


def _reset_caches():
    _category_cache.clear()
    _tool_name_cache.clear()

# --- GLOBAL CANONICAL WORK AND TOOL MANAGEMENT ---

def get_or_create_main_category(canonical_name: str) -> tuple[str, str]:
    from .llm_functions import judge_category_match, batch_create_missing
    key = canonical_name.lower().strip()
    if key in _category_cache: return _category_cache[key]

    emb = pinecone_embed_text(canonical_name)
    cands = pinecone_query(emb, top_k=10, filter_dict={"type": "category"})
    cat_id = judge_category_match(canonical_name, cands)

    if cat_id:
        doc = db.collection(COL_CATEGORIES).document(cat_id).get().to_dict()
        if doc:
            _category_cache[key] = (doc["category_id"], doc["name"])
            return _category_cache[key]

    res = batch_create_missing([{"idx": 0, "category": canonical_name, "task": "General Work"}], [])
    cat_name = res["cws"].get(0, {}).get("category", canonical_name)
    cat_desc = res["cws"].get(0, {}).get("description", f"Trade category: {canonical_name}")
    
    cat_id = str(uuid.uuid4())
    db.collection(COL_CATEGORIES).document(cat_id).set({
        "category_id": cat_id,
        "name": cat_name,
        "description": cat_desc,
        "type": "category",
        "createdAt": now_ts()
    })
    pinecone_upsert(cat_id, pinecone_embed_text(f"{cat_name} {cat_desc}"), {"category_id": cat_id, "name": cat_name, "type": "category"})
    
    _category_cache[key] = (cat_id, cat_name)
    return cat_id, cat_name

def get_or_create_canonical_tool(raw_tool_name):
    raw_tool_name = str(raw_tool_name).strip()
    if len(raw_tool_name) < 2: return None

    search_input = f"{raw_tool_name}: general repair/installation equipment."

    embedding = pinecone_embed_text(search_input)

    matches = pinecone_query(embedding, top_k=8, filter_dict={"type": "tool"})

    selected_tool_id = None

    if matches:
        selected_tool_id = llm_select_best_match(raw_tool_name, matches)

    if selected_tool_id:
        doc = db.collection(COL_TOOLS).document(selected_tool_id).get().to_dict()
        print(f"🔧 Tool Match (LLM Selected): '{raw_tool_name}' -> '{doc['name']}'")
        return doc['name']

    print(f"🆕 Creating New Tool (Extreme Fallback): {raw_tool_name}")
    clean_name, description = llm_generate_new_entity(raw_tool_name, "tool")

    if not clean_name:
        clean_name = raw_tool_name
        description = f"User defined tool: {raw_tool_name}"

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


def process_worker_profile(description: str) -> list[dict]:
    from .llm_functions import extract_and_classify_profile, batch_judge_cw_candidates, batch_judge_tool_candidates, batch_create_missing
    _reset_caches()
    
    profile = extract_and_classify_profile(description)
    jobs, tools = profile.get("jobs", []), profile.get("tools", [])
    if not jobs: return []

    cat_map = {}
    for j in jobs:
        if j["category"] not in cat_map: cat_map[j["category"]] = get_or_create_main_category(j["category"])

    unique_jobs = list({(j["category"].lower(), j["task"].lower()): j for j in jobs}.values())
    jobs_with_cands = []
    for idx, job in enumerate(unique_jobs):
        cat_id, cat_name = cat_map[job["category"]]
        cands = pinecone_query(pinecone_embed_text(f"{cat_name} {job['task']}"), top_k=10, filter_dict={"type": "job"})
        jobs_with_cands.append({
            "idx": idx, "category": cat_name, "task": job["task"], "cat_id": cat_id,
            "candidates": [{"id": c.get("id"), "category": c.get("metadata", {}).get("category", ""), "name": c.get("metadata", {}).get("canonicalWork", "")} for c in cands]
        })

    unique_tools = list({t["name"].lower(): t for t in tools}.values())
    tools_with_cands = []
    for idx, t in enumerate(unique_tools):
        cands = pinecone_query(pinecone_embed_text(f"{t.get('trade','')} {t['name']}"), top_k=10, filter_dict={"type": "tool"})
        tools_with_cands.append({
            "idx": idx, "name": t["name"], "trade": t.get("trade", ""),
            "candidates": [{"id": c.get("id"), "name": c.get("metadata", {}).get("name", "")} for c in cands]
        })

    cw_verdicts = batch_judge_cw_candidates(jobs_with_cands)
    tool_verdicts = batch_judge_tool_candidates(tools_with_cands)

    missing_cws = [j for j in jobs_with_cands if not cw_verdicts.get(j["idx"])]
    missing_tools = [t for t in tools_with_cands if not tool_verdicts.get(t["idx"])]
    created = batch_create_missing(missing_cws, missing_tools)

    tool_id_map = {}
    for t in tools_with_cands:
        idx, v_id = t["idx"], tool_verdicts.get(t["idx"])
        if v_id:
            doc = db.collection(COL_TOOLS).document(v_id).get().to_dict()
            if doc: tool_id_map[idx] = doc["name"]
        
        if idx not in tool_id_map:
            rec = created["tools"].get(idx, {})
            t_name, t_desc = rec.get("name", t["name"]), rec.get("description", "Tool.")
            t_id = slugify(t_name)
            if not db.collection(COL_TOOLS).document(t_id).get().exists:
                db.collection(COL_TOOLS).document(t_id).set({"tool_id": t_id, "name": t_name, "type": "tool", "createdAt": now_ts(), "description": t_desc})
                pinecone_upsert(t_id, pinecone_embed_text(f"{t_name} {t_desc}"), {"name": t_name, "type": "tool"})
            tool_id_map[idx] = t_name

    trade_tools = {}
    for t in tools_with_cands: trade_tools.setdefault(t.get("trade", "General"), []).append(tool_id_map[t["idx"]])

    results = []
    for j in jobs_with_cands:
        idx, v_id = j["idx"], cw_verdicts.get(j["idx"])
        if v_id:
            doc = db.collection(COL_CW).document(v_id).get().to_dict()
            if doc:
                results.append(doc)
                continue
        
        rec = created["cws"].get(idx, {})
        cw_name, cw_desc = rec.get("name", j["task"]), rec.get("description", "Task.")
        cat_id, cat_name = j["cat_id"], j["category"]
        cw_id = str(uuid.uuid4())
        
        doc_data = {
            "cw_id": cw_id, "canonicalWork": cw_name, "description": cw_desc, 
            "category_id": cat_id, "category": cat_name, 
            "requiredTools": list(set(trade_tools.get(j["category"], []))),
            "createdAt": now_ts()
        }
        db.collection(COL_CW).document(cw_id).set(doc_data)
        pinecone_upsert(cw_id, pinecone_embed_text(f"{cat_name} {cw_name} {cw_desc}"), {"cw_id": cw_id, "canonicalWork": cw_name, "category_id": cat_id, "category": cat_name, "type": "job"})
        results.append(doc_data)

    return results
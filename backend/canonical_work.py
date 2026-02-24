# canonical_work.py
import uuid
from datetime import datetime, timezone
from .firebase_init import db
from .constants import COL_CATEGORIES, COL_TOOLS, COL_CW
from .ai_utils import pinecone_embed_text, pinecone_query, pinecone_upsert, run_llm
from .llm_functions import llm_select_best_match, llm_generate_new_entity
from .utils import slugify, now_ts

# --- GLOBAL CANONICAL WORK AND TOOL MANAGEMENT ---

def get_or_create_main_category(raw_category_name):
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
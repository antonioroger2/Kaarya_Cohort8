# llm_functions.py
import json
import re
import uuid
from .ai_utils import run_llm, pinecone_embed_text, pinecone_query
from .firebase_init import db
from .constants import COL_CATEGORIES, COL_TOOLS, COL_CW
from .utils import slugify

_PINECONE_K = 10
_MAX_INTENTS = 10

_SYSTEM_PREAMBLE = """\
You are a strict trade-classification AI.
ABSOLUTE RULES:
1. Never confuse different trades. Electrician ≠ Mason ≠ Plumber ≠ Painter.
2. Never force-fit. Wrong match = NONE. No "least wrong" answers.
3. Output ONLY valid raw JSON. No markdown, no prose.
4. Use real-world macro trade names (Electrician, Plumber, Mason, Carpenter…).
"""


def _parse_json(raw):
    try:
        text = str(raw).strip()
        if "```json" in text:
            text = text.split("```json", 1)[1].rsplit("```", 1)[0].strip()
        elif "```" in text:
            text = text.split("```", 1)[1].rsplit("```", 1)[0].strip()
        return json.loads(text)
    except Exception as e:
        print(f"LLM JSON parse error: {e} | Raw: {str(raw)[:200]}")
        return {}

# --- LLM STRICT MODE FUNCTIONS ---

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
        if response.startswith('['):
            pass
        elif "```json" in response:
            response = response.split("```json", 1)[1].rsplit("```", 1)[0].strip()
        elif "```" in response:
            response = response.split("```", 1)[1].rsplit("```", 1)[0].strip()

        data = json.loads(response)

        if isinstance(data, list):
            return data
        else:
            print(f"Analyze Hierarchy Failed: JSON loaded successfully but was not a list. Type: {type(data)}")
            return []

    except Exception as e:
        print(f"Analyze Hierarchy Failed: JSON Parse Failure: {e} | Raw Response: {response[:150]}...")
        return []


def extract_and_classify_profile(description: str) -> dict:
    prompt = f"""\
Worker description: "{description}"

Analyze this description and output ONE JSON object with these keys:
"jobs": list of distinct trade tasks the worker performs.
    Each: {{"category": "Trade", "task": "2-4 word task name"}}
"tools": list of macro-level reusable tools mentioned or implied.
    Each: {{"name": "Generic Tool Name", "trade": "which trade uses it"}}
"excluded_trades": list of trades the worker explicitly said they do NOT do.

Example:
{{
    "jobs": [{{"category": "Electrician", "task": "Wire Repair"}}],
    "tools": [{{"name": "Voltage Tester", "trade": "Electrician"}}],
    "excluded_trades": ["Mason"]
}}
JSON:"""
    try:
        raw = run_llm(_SYSTEM_PREAMBLE + "\n" + prompt, max_new_tokens=800)
        data = _parse_json(raw)
        if not isinstance(data, dict):
            return {"jobs": [], "tools": [], "excluded_trades": []}
        return {
            "jobs": [j for j in data.get("jobs", []) if isinstance(j, dict) and j.get("category") and j.get("task")],
            "tools": [t for t in data.get("tools", []) if isinstance(t, dict) and t.get("name")],
            "excluded_trades": data.get("excluded_trades", []),
        }
    except Exception as e:
        print(f"extract_and_classify_profile error: {e}")
        return {"jobs": [], "tools": [], "excluded_trades": []}


def batch_judge_cw_candidates(jobs_with_candidates: list) -> dict:
    if not jobs_with_candidates: return {}
    blocks = []
    for item in jobs_with_candidates:
        cands = item.get("candidates", [])
        if not cands: continue
        lines = [f'  {i+1}. ID:{c["id"]} | {c.get("category","?")} -> {c.get("name","?")}' for i, c in enumerate(cands)]
        blocks.append(f'INTENT {item["idx"]}: {item["category"]} / {item["task"]}\n' + '\n'.join(lines))
        
    prompt = f"""\
For each INTENT below, decide if any candidate is a GENUINE match.
Wrong trade or different task = NOT a match -> null.
{chr(10).join(blocks)}
Output JSON mapping index to matched ID or null: {{"0": "id_or_null"}}"""
    
    raw = run_llm(_SYSTEM_PREAMBLE + "\n" + prompt, max_new_tokens=300)
    data = _parse_json(raw)
    results = {int(k): (v if isinstance(v, str) and len(v)>4 else None) for k, v in (data or {}).items() if str(k).isdigit()}
    for item in jobs_with_candidates: results.setdefault(item["idx"], None)
    return results


def batch_judge_tool_candidates(tools_with_candidates: list) -> dict:
    if not tools_with_candidates: return {}
    blocks = []
    for item in tools_with_candidates:
        cands = item.get("candidates", [])
        if not cands: continue
        lines = [f'  {i+1}. ID:{c["id"]} | {c.get("name","?")}' for i, c in enumerate(cands)]
        blocks.append(f'TOOL {item["idx"]}: "{item["name"]}"\n' + '\n'.join(lines))
        
    prompt = f"""\
For each TOOL below, decide if any candidate is FUNCTIONALLY IDENTICAL.
{chr(10).join(blocks)}
Output JSON mapping index to matched ID or null: {{"0": "id_or_null"}}"""
    
    raw = run_llm(_SYSTEM_PREAMBLE + "\n" + prompt, max_new_tokens=300)
    data = _parse_json(raw)
    results = {int(k): (v if isinstance(v, str) and len(v)>1 else None) for k, v in (data or {}).items() if str(k).isdigit()}
    for item in tools_with_candidates: results.setdefault(item["idx"], None)
    return results


def batch_create_missing(missing_cws: list, missing_tools: list) -> dict:
    if not missing_cws and not missing_tools: return {"cws": {}, "tools": {}}
    cw_lines = [f'  CW{i["idx"]}: category="{i["category"]}" task="{i["task"]}"' for i in missing_cws]
    tool_lines = [f'  TOOL{i["idx"]}: name="{i["name"]}" trade="{i.get("trade","")}"' for i in missing_tools]
    
    prompt = f"""\
Generate canonical records for all items below.
NEW CWS:\n{chr(10).join(cw_lines)}
NEW TOOLS:\n{chr(10).join(tool_lines)}
Output JSON with "cws" and "tools" mapping index to record:
{{"cws": {{"0": {{"category":"...", "name":"...", "description":"..."}}}}, "tools": {{"0": {{"name":"...", "description":"..."}}}}}}"""
    
    raw = run_llm(_SYSTEM_PREAMBLE + "\n" + prompt, max_new_tokens=2000)
    data = _parse_json(raw)
    if not isinstance(data, dict): return {"cws": {}, "tools": {}}
    return {
        "cws": {int(k): v for k, v in data.get("cws", {}).items() if str(k).isdigit()},
        "tools": {int(k): v for k, v in data.get("tools", {}).items() if str(k).isdigit()}
    }


def judge_category_match(canonical_name: str, candidates: list) -> str | None:
    if not candidates: return None
    lines = [f'{i+1}. ID:{c["id"]} | {c.get("metadata",{}).get("name","?")}' for i, c in enumerate(candidates)]
    prompt = f"""Trade to find: "{canonical_name}"
Candidates:
{chr(10).join(lines)}
Is any candidate the SAME trade?
Reply ONLY with the integer index or NONE."""
    res = run_llm(_SYSTEM_PREAMBLE + "\n" + prompt, max_new_tokens=5).strip().upper()
    try:
        idx = int(res)
        if 1 <= idx <= len(candidates): return candidates[idx - 1].get("id")
    except: pass
    return None


def llm_analyze_review(review_text, original_rating, primary_job):
    """
    The Profile Healer AI. Parses review text to:
    1. Adjust the raw star rating based on actual sentiment.
    2. Extract a standalone professionalism score.
    3. Discover new, unlisted skills the worker performed.
    """
    prompt = f"""Analyze this customer review: "{review_text}"
Original Rating Given: {original_rating}/5
Primary Job Hired For: {primary_job}

Task 1 (Sentiment): Determine 'adjusted_rating' (1.0 - 5.0). If they gave 5 stars but complained, penalize it. If they gave 3 stars but the text is glowing, boost it.
Task 2 (Professionalism): Determine 'professionalism' (1.0 - 5.0) based on mentions of cleanliness, attitude, or punctuality. If not mentioned, default to the adjusted_rating.
Task 3 (Skill Discovery): Identify 'hidden_skills'. Did the worker do ANY OTHER distinct, macro-level tasks besides "{primary_job}"? (e.g., "he also fixed my doorbell").

Return STRICT JSON ONLY:
{{
  "adjusted_rating": 4.2,
  "professionalism": 3.0,
  "hidden_skills": [
    {{"category": "Electrical", "task": "Doorbell Repair"}}
  ]
}}"""

    response = run_llm(prompt, max_new_tokens=200)
    
    try:
        if "```json" in response:
            response = response.split("```json", 1)[1].rsplit("```", 1)[0].strip()
        elif "```" in response:
            response = response.split("```", 1)[1].rsplit("```", 1)[0].strip()

        match = re.search(r'\{.*?\}', response, re.DOTALL)
        if match:
            data = json.loads(match.group(0))
            return float(data.get("adjusted_rating", original_rating)), float(data.get("professionalism", original_rating)), data.get("hidden_skills", [])
            
    except Exception as e:
        print(f"Profile Healer Parse Error: {e} | Raw: {response}")
        
    return original_rating, original_rating, []
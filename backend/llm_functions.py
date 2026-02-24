# llm_functions.py
import json
import re
import uuid
from .ai_utils import run_llm, pinecone_embed_text, pinecone_query
from .firebase_init import db
from .constants import COL_CATEGORIES, COL_TOOLS, COL_CW
from .utils import slugify

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
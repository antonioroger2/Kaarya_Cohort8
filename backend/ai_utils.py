# ai_utils.py
import requests
import time
import json
from .config import (
    GROQ_API_KEY, PINECONE_API_KEY, EMBEDDING_DIMENSION, PINECONE_MODEL,
    GROQ_LLM_URL, GROQ_MODEL, MAX_LLM_RETRIES, PINECONE_INDEX_HOST,
    PINECONE_EMBED_URL, headers_llm, headers_pinecone
)

# --- HELPER FUNCTIONS: AI & VECTOR ---

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
# config.py
import os
from dotenv import load_dotenv

load_dotenv()

# --- CONFIGURATION ---
API_SECRET = os.environ.get("OTP_API_SECRET")
if not API_SECRET:
    raise ValueError("OTP_API_SECRET environment variable is required")

FIREBASE_CRED = os.environ.get("FIREBASE_CRED", "firebase-service-account-key.json")
MISSED_CALL_NO = os.environ.get("MISSED_CALL_NO")
if not MISSED_CALL_NO:
    raise ValueError("MISSED_CALL_NO environment variable is required")

EMAIL_SUFFIX = "@kaaryaconnect.app"
GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
if not GROQ_API_KEY:
    raise ValueError("GROQ_API_KEY environment variable is required")

PINECONE_API_KEY = os.environ.get("PINECONE_API_KEY")
if not PINECONE_API_KEY:
    raise ValueError("PINECONE_API_KEY environment variable is required")

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
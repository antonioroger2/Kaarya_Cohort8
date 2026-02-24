# firebase_init.py
import firebase_admin
from firebase_admin import credentials, firestore
from .config import FIREBASE_CRED

# --- INIT FIREBASE ---
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate(FIREBASE_CRED)
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"FIREBASE INIT ERROR: {e}")

db = firestore.client()
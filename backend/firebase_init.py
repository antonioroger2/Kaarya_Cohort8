# firebase_init.py
import firebase_admin
from firebase_admin import credentials, firestore
from .config import FIREBASE_CRED
import os

# --- INIT FIREBASE ---
if not firebase_admin._apps:
    try:
        cred_path = os.path.join(os.path.dirname(__file__), FIREBASE_CRED)
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"FIREBASE INIT ERROR: {e}")

db = firestore.client() if firebase_admin._apps else None
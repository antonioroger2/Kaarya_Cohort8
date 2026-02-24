# utils.py
import secrets
import hashlib
import re
from datetime import datetime, timedelta, timezone
from functools import wraps
from flask import request
from .config import API_SECRET, HOUR_OFFSET, SLOT_COUNT
from .firebase_init import db

# --- HELPER FUNCTIONS: CORE ---
def require_secret(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        secret = request.headers.get("x-secret-key")
        if secret != API_SECRET:
            return
        return f(*args, **kwargs)
    return wrapper

def now_ts():
    return db.firestore.SERVER_TIMESTAMP

def sanitize_phone(phone):
    if not phone: return None
    return "".join(c for c in phone if c.isdigit() or c == '+')

def gen_otp(length=6):
    return str(secrets.randbelow(10**length)).zfill(length)

def hash_code(code):
    return hashlib.sha256(code.encode()).hexdigest()

def hours_to_mask(start_hour, end_hour):
    s = int(start_hour) - HOUR_OFFSET
    e = int(end_hour) - HOUR_OFFSET
    if e == SLOT_COUNT: e = 24
    if s < 0 or e > SLOT_COUNT or s > e:
        raise ValueError(f"Invalid hours range: {start_hour}-{end_hour}. Valid: 0..24")
    length = e - s
    if length <= 0: return 0
    return ((1 << length) - 1) << s

def sim_sms_message(template, **kwargs):
    return template.format(**kwargs)

def slugify(text):
    text = str(text).lower()
    text = re.sub(r'[^a-z0-9\s]+', '', text)
    text = re.sub(r'\s+', '_', text)
    return text.strip('_')
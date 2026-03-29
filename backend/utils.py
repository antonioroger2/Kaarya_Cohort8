# utils.py
import secrets
import hashlib
import re
from datetime import datetime, timedelta, timezone
from functools import wraps
from flask import request
from google.cloud.firestore_v1.transforms import SERVER_TIMESTAMP
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
    return SERVER_TIMESTAMP

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

# ==========================================
# LANGUAGE & LOCALIZATION UTILITIES
# ==========================================

# TODO: Implement native language support for SMS and IVR
# Add language detection based on worker's location/state
# Support Hindi and major regional languages (Tamil, Telugu, Bengali, etc.)

def detect_worker_language(worker_id: str) -> str:
    """
    Detect worker's preferred language based on their profile/location.
    
    TODO: Implement language detection logic
    - Check worker's state/location from profile
    - Map to appropriate language (Hindi, Tamil, Telugu, etc.)
    - Default to English if not detected
    
    Returns:
        str: Language code (e.g., 'hi', 'ta', 'te', 'en')
    """
    # TODO: Query worker's location/state from Firestore
    # For now, return English as default
    return 'en'


def translate_sms_template(template_key: str, language: str, **kwargs) -> str:
    """
    Translate SMS template to worker's native language.
    
    TODO: Implement translation system
    - Create translation dictionaries for each language
    - Handle variable substitution in translated text
    - Support RTL languages if needed
    
    Args:
        template_key: Key of the template (e.g., 'T_JOB_ALERT')
        language: Language code
        **kwargs: Template variables
    
    Returns:
        str: Translated template with variables substituted
    """
    # TODO: Implement actual translation
    # For now, return English template
    from .constants import T_JOB_ALERT, T_START_OTP, T_END_OTP
    
    template_map = {
        'T_JOB_ALERT': T_JOB_ALERT,
        'T_START_OTP': T_START_OTP,
        'T_END_OTP': T_END_OTP
    }
    
    template = template_map.get(template_key, "")
    return template.format(**kwargs)


def translate_ivr_script(script_key: str, language: str, **kwargs) -> str:
    """
    Translate IVR script to worker's native language for text-to-speech.
    
    TODO: Implement IVR script translation
    - Create voice-friendly translations
    - Ensure proper pronunciation guides
    - Test with TTS engines
    
    Args:
        script_key: Key of the script (e.g., 'job_alert', 'otp_start')
        language: Language code
        **kwargs: Script variables
    
    Returns:
        str: Translated script with variables substituted
    """
    # TODO: Implement actual translation
    # For now, return English script
    script_map = {
        'job_alert': "Hello. You have a new Kaarya job request. Location is {locality} on {date}. Time: {from_time} to {to_time}. Total payout: {wage} rupees. To accept this job, press 1. To decline, press 2.",
        'otp_start': "Hello. Your job start code for {locality} is {otp}. I repeat, {otp}. Please give this code to the customer to start the job.",
        'otp_end': "Hello. Your job completion code for {locality} is {otp}. Please give this code to the customer to close the job and release your payment."
    }
    
    script = script_map.get(script_key, "")
    return script.format(**kwargs)
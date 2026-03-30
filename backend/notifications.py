import os
import requests
from firebase_admin import messaging
from google.cloud import firestore
from .firebase_init import db
from .constants import COL_BOOKINGS, COL_WORKERS

# ==========================================
# 1. CORE NOTIFICATION SENDERS (ACTUAL APIs)
# ==========================================

def send_fcm_push(worker_id: str, title: str, body: str, data: dict = None) -> bool:
    """Sends a real Firebase Cloud Messaging push notification."""
    try:
        worker_doc = db.collection(COL_WORKERS).document(worker_id).get()
        if not worker_doc.exists:
            return False
            
        worker_data = worker_doc.to_dict()
        fcm_token = worker_data.get("fcmToken") # Assuming you store this during Flutter login
        
        if not fcm_token:
            print(f"No FCM token found for worker {worker_id}")
            return False

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            token=fcm_token
        )
        response = messaging.send(message)
        print(f"FCM Push successful: {response}")
        return True
    except Exception as e:
        print(f"FCM Push Failed: {e}")
        return False


def _save_inbox_message(recipient_id: str, payload: dict):
    """Save a notification-like message under inbox/<userId>/content and prune to last 5."""
    try:
        from .utils import now_ts

        payload = {**payload}
        payload.setdefault("isRead", False)
        payload.setdefault("createdAt", now_ts())

        content_ref = db.collection("inbox").document(recipient_id).collection("content")
        content_ref.add(payload)

        # Keep only latest 5 messages
        older_docs = content_ref.order_by("createdAt", direction=firestore.Query.DESCENDING).offset(5).stream()
        batch = db.batch()
        for doc in older_docs:
            batch.delete(doc.reference)
        batch.commit()
    except Exception as e:
        print(f"Inbox save failed for {recipient_id}: {e}")


def send_twilio_sms(phone_number: str, message_body: str) -> bool:
    """Sends a real SMS using the Twilio REST API."""
    try:
        account_sid = os.getenv("TWILIO_ACCOUNT_SID")
        auth_token = os.getenv("TWILIO_AUTH_TOKEN")
        from_number = os.getenv("TWILIO_PHONE_NUMBER")

        if not all([account_sid, auth_token, from_number]):
            print("Twilio credentials missing in .env")
            return False

        url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"
        data = {
            "From": from_number,
            "To": phone_number,
            "Body": message_body
        }
        
        response = requests.post(url, auth=(account_sid, auth_token), data=data, timeout=10)
        return response.status_code in [200, 201]
    except Exception as e:
        print(f"Twilio SMS Failed: {e}")
        return False


def trigger_exotel_ivr_call(phone_number: str, custom_script: str) -> bool:
    """Triggers a real Exotel IVR Call, passing custom text for the bot to read."""
    try:
        api_key = os.getenv("EXOTEL_API_KEY")
        api_token = os.getenv("EXOTEL_API_TOKEN")
        sid = os.getenv("EXOTEL_SID")
        caller_id = os.getenv("EXOTEL_CALLER_ID") # Your virtual Exotel number
        app_id = os.getenv("EXOTEL_APP_ID")       # The ID of your Exotel IVR Flow

        if not all([api_key, api_token, sid, caller_id, app_id]):
            print("Exotel credentials missing in .env")
            return False

        url = f"https://{api_key}:{api_token}@api.exotel.com/v1/Accounts/{sid}/Calls/connect.json"
        
        # We pass the custom_script in "CustomField" so the Exotel flow can use Text-To-Speech to read it
        data = {
            "From": phone_number,
            "To": caller_id,
            "CallerId": caller_id,
            "Url": f"http://my.exotel.com/{sid}/exoml/start_voice/{app_id}",
            "CustomField": custom_script 
        }
        
        response = requests.post(url, data=data, timeout=15)
        return response.status_code == 200
    except Exception as e:
        print(f"Exotel IVR Failed: {e}")
        return False


# ==========================================
# 2. ESCALATION BUSINESS LOGIC
# ==========================================

def escalate_job_assignment(booking_id: str, worker_id: str, escalation_level: int):
    """Fetches real DB data and triggers the appropriate notification level."""
    booking_doc = db.collection(COL_BOOKINGS).document(booking_id).get()
    worker_doc = db.collection(COL_WORKERS).document(worker_id).get()

    if not booking_doc.exists or not worker_doc.exists:
        return

    b_data = booking_doc.to_dict()
    w_data = worker_doc.to_dict()
    
    locality = b_data.get("location", {}).get("locality", "your area")
    date = b_data.get("date", "Today")
    from_time = f"{b_data.get('startHour', 8):02d}:00"
    to_time = f"{b_data.get('endHour', 10):02d}:00"
    wage = b_data.get("wage", 0) + b_data.get("ta", 0)
    worker_phone = w_data.get("phone")

    if escalation_level == 1:
        # Level 1: FCM Push Notification
        title = "New Job Request! 🚨"
        body = f"Job at {locality} on {date}, {from_time}-{to_time}. Earn ₹{wage}."
        data = {"booking_id": booking_id, "action": "open_job_request"}
        _save_inbox_message(worker_id, {
            "recipientId": worker_id,
            "title": title,
            "message": body,
            "type": "new_booking_request",
            "bookingId": booking_id,
        })
        send_fcm_push(worker_id, title, body, data)

    elif escalation_level == 2:
        # Level 2: SMS
        from .constants import T_JOB_ALERT, MISSED_CALL_NO
        from .utils import sim_sms_message

        message = sim_sms_message(
            T_JOB_ALERT,
            role="WORKER",
            locality=locality,
            date=date,
            from_time=from_time,
            to_time=to_time,
            hours=str(b_data.get("endHour", 10) - b_data.get("startHour", 8)),
            wage=wage,
            details=b_data.get("notes", "General Repair"),
            missed_call_no=MISSED_CALL_NO or "0000000000"
        )
        if worker_phone:
            send_twilio_sms(worker_phone, message)

    elif escalation_level == 3:
        # Level 3: IVR Call
        # TODO: Add native language support for IVR scripts
        # Use translate_ivr_script() function to get localized voice prompts
        script = f"Hello. You have a new Kaarya job request. Location is {locality} on {date}. Time: {from_time} to {to_time}. Total payout: {wage} rupees. To accept this job, press 1. To decline, press 2."
        if worker_phone:
            trigger_exotel_ivr_call(worker_phone, script)


def escalate_otp_delivery(booking_id: str, worker_id: str, otp_type: str, otp_code: str, escalation_level: int):
    """Delivers the Start/End OTP via Push, SMS, or Voice Call."""
    booking_doc = db.collection(COL_BOOKINGS).document(booking_id).get()
    worker_doc = db.collection(COL_WORKERS).document(worker_id).get()

    if not booking_doc.exists or not worker_doc.exists:
        return

    b_data = booking_doc.to_dict()
    worker_phone = worker_doc.to_dict().get("phone")
    locality = b_data.get("location", {}).get("locality", "your area")

    if escalation_level == 1:
        # Level 1: FCM Push Notification
        title = "Job Start OTP" if otp_type == "start" else "Job End OTP & Payment"
        body = f"Your code for the {locality} job is: {otp_code}. Ask the customer to enter this."
        data = {"booking_id": booking_id, "otp": otp_code, "type": otp_type}
        notif_type = "job_confirmed" if otp_type == "start" else "job_completed"
        _save_inbox_message(worker_id, {
            "recipientId": worker_id,
            "title": title,
            "message": body,
            "type": notif_type,
            "bookingId": booking_id,
            "otpCode": otp_code,
            "otpType": otp_type,
        })
        send_fcm_push(worker_id, title, body, data)

    elif escalation_level == 2:
        # Level 2: SMS
        from .constants import T_START_OTP, T_END_OTP
        from .utils import sim_sms_message
        
        hours = b_data.get("endHour", 10) - b_data.get("startHour", 8)
        wage = b_data.get("wage", 0) + b_data.get("ta", 0)

        if otp_type == "start":
            message = sim_sms_message(
                T_START_OTP,
                locality=locality,
                date=b_data.get("date", ""),
                from_time=f"{b_data.get('startHour', 8):02d}:00",
                to_time=f"{b_data.get('endHour', 10):02d}:00",
                otp=otp_code,
                wage=wage,
                wph=(wage // hours if hours > 0 else 0)
            )
        else:
            message = sim_sms_message(
                T_END_OTP,
                locality=locality,
                date=b_data.get("date", ""),
                otp=otp_code,
                wage=wage,
                hours=hours
            )
            
        if worker_phone:
            send_twilio_sms(worker_phone, message)

    elif escalation_level == 3:
        # Level 3: IVR Call
        # TODO: Add native language support for IVR scripts
        # Use translate_ivr_script() function to get localized voice prompts
        if otp_type == "start":
            script = f"Hello. Your job start code for {locality} is {otp_code}. I repeat, {otp_code}. Please give this code to the customer to start the job."
        else:
            script = f"Hello. Your job completion code for {locality} is {otp_code}. Please give this code to the customer to close the job and release your payment."
            
        if worker_phone:
            trigger_exotel_ivr_call(worker_phone, script)
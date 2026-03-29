# constants.py

# --- DB COLLECTION NAMES ---
# COL_USERS = "users"  # Unused, hardcoded "users" used instead
COL_WORKERS = "workers"
COL_BOOKINGS = "bookings"
COL_CW = "canonical_works"
COL_TOOLS = "tools"
COL_OTP = "otp"
COL_VERIFIED = "verified_signups"
# COL_HISTORY = "raw_to_canonical_history"  # Unused in active code
COL_CATEGORIES = "main_categories"

# TODO: Add language preference field to worker profiles
# Schema: preferredLanguage: str (e.g., 'hi', 'ta', 'te', 'en')

# --- SMS TEMPLATES ---
# TODO: Add native language support (Hindi/Regional) for SMS templates
# Create functions to detect worker's preferred language and translate templates
T_JOB_ALERT = ("[{role}] JOB ALERT: Service requested at {locality} on {date}. "
             "Time: {from_time} to {to_time} (approx. {hours} hours) at ₹{wage}. "
             "Notes: {details}. To accept, reply 'ACCEPT' or use the app. Missed call: {missed_call_no} ~ Kaarya")
T_REMINDER = ("30 MINUTE REMINDER: Your [{role}] job at {locality} starts at {from_time} on {date}. "
              "Full Address: {address}. For directions, click: {gmaps} ~ Team Kaarya")
T_START_OTP = ("JOB START OTP: Your code for the {locality} job on {date} ({from_time}-{to_time}) is {otp}. "
              "Total Est: ₹{wage} ({wph}/hr). Share with customer to confirm START.")
T_END_OTP = ("JOB END OTP: Your completion code for the {locality} job on {date} is {otp}. "
              "Elapsed Time: {hours} hours (Final Wage: ₹{wage}). SHARE WITH CUSTOMER to confirm payment received.")
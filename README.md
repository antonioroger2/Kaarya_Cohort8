# Kaarya Connect

>A hyperlocal gig-economy platform for India’s informal workforce.
Smart bookings powered by AI — customers describe what they need in plain language, and workers are matched, scheduled, and verified automatically.
---

Kaarya Connect is built to solve a real problem: India's ₹5,000+ crore home-services market is largely unorganized, and both workers and customers are affected. Customers struggle to find trustworthy help, while skilled workers lack visibility and steady income opportunities.

## People-First, Non-Employer Model

Unlike platforms such as Uber or Urban Company, Kaarya Connect is not built on a contractor–employee dynamic. Workers are not employees and are not bound by restrictive contracts.

The platform simply provides verified bookings, visibility, and access to consistent opportunities. Kaarya Connect is designed to empower skilled professionals to remain independent while helping customers access reliable services.

---

## The Repository Implements a Platform That:

* Connects customers with independent service providers
* Provides verified bookings
* Improves provider visibility
* Facilitates consistent service opportunities

This repository was originally built for a hackathon, where it placed Top 120 out of thousands of entries. Development has since been paused, but the underlying architecture remains far from basic.

---

## What It Does

**For customers:**
- Browse nearby workers filtered by skill, locality, and rating
- Describe a job in plain text — the AI categorizes it, infers required tools, scores candidates, and surfaces the best match
- Book a specific worker or let the system auto-assign
- OTP-verified job start and end — both parties confirm before the clock starts and after it stops
- Get warned automatically if a worker is being booked outside their optimal service radius
- Rate and review workers on completion

**For workers:**
- Onboard by writing a free-form professional summary — AI extracts structured skill chips and tool requirements, no dropdown required
- Accept or decline job requests with full context (location, pay, notes, distance)
- Profile continuously updated as reviews come in — hidden skills surface passively, reputation scores refine automatically
- Calendar view of upcoming jobs
- Emergency SOS on the job

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (iOS, Android, Web) |
| Backend | Python / Flask |
| Database | Firebase Firestore |
| Auth | Firebase Authentication |
| Vector Search | Pinecone (`llama-text-embed-v2`, 1024-dim) |
| LLM | Groq API (Llama 3.1-8b-instant) |

---
## Local Development Setup

### Prerequisites
- Flutter SDK (latest stable version)
- Python 3.8+
- pip
- Firebase project with service account key
- Pinecone account
- Groq API key

### Backend Setup
1. Navigate to the `backend` directory:
   ```bash
   cd backend
   ```

2. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Set up environment variables by copying and editing `.env`:
   - Copy the existing `.env` file or create one with required variables (see config.py for details)
   - Ensure `FIREBASE_CRED` points to `firebase-service-account-key.json` (placeholder created)
   - Obtain actual Firebase service account key from Firebase Console and replace the placeholder

4. Run the backend server:
   ```bash
   python main.py
   ```
   The server will start on `http://127.0.0.1:5000`

### Flutter App Setup
1. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

2. Ensure `.env` file is present in the root directory with required API keys.

3. Run the Flutter app in debug mode:
   ```bash
   flutter run
   ```
   In debug mode, the app automatically connects to the local backend at `http://127.0.0.1:5000`. In release mode, it uses the production server.

### Environment Variables
- Backend: See `backend/.env` for required variables
- Flutter: See `.env` for API keys

Note: The Firebase service account key file is gitignored to prevent accidental commits.

Escrow-based OTP Job Cycle handshake and an automated Push-to-IVR escalation protocol to ensure trust and safety across diverse network conditions

## Core AI Systems

### 1. Self-Healing Skill Taxonomy

Most platforms force workers into predefined boxes. Kaarya inverts this — workers describe themselves naturally, and the system builds structure from that.

**Onboarding:**
1. Worker writes a free-form professional summary (minimum 60 words)
2. Groq LLM (Llama 3.1) parses the text and extracts an array of `{ category, task, tools }` objects at a macro level
3. Each extracted task is embedded via Pinecone's inference API and compared (cosine similarity) against the existing Canonical Work (CW) database
4. **Match found** → maps to the existing canonical entry, no duplicates created
5. **No match** → LLM autonomously generates a new Canonical Work entry with a normalized name, description, and required toolset, then upserts it into Pinecone for all future use

The taxonomy is self-expanding and self-normalizing. A plumber who calls it "pipe welding" and one who writes "soldering copper joints" map to the same canonical task automatically. Every new worker makes the system smarter for the next one.

---

### 2. Multi-Factor Worker Matching Engine

When a job request comes in, every candidate worker is scored and ranked:

```
Final Score = (Skill Relevance × 0.60) + (Reputation × 0.20) + (Tool Capability × 0.20)
```

- **Skill Relevance (60%):** Alignment between the worker's verified Canonical Work history and the AI-parsed job request
- **Tool Capability (20%):** Quantitative ratio of tools the worker owns against the macro-level tools the job requires
- **Reputation (20%):** Aggregated historical ratings across all completed bookings

The top-ranked candidates receive the job request simultaneously. First to accept gets it — with full transactional protection against double-booking.

---

### 3. Profile Healer & Passive Skill Discovery

The platform doesn't just collect reviews — it reads them.

After every job completion, the review text is analyzed by the LLM:

- **Sentiment Alignment:** If the written review contradicts the star rating (e.g., a complaint buried inside a 5-star submission), the system adjusts the effective score to reflect actual sentiment
- **Professionalism Scoring:** The AI independently extracts dimension-level scores for punctuality, attitude, and cleanliness from unstructured review text — building a richer reputation profile than a single number can capture
- **Passive Skill Discovery:** If a review mentions work the worker performed outside their listed skills (e.g., *"He fixed my doorbell while repairing the AC"*), the system flags this as a hidden skill and suggests adding it to the worker's verified profile

Worker profiles improve automatically over time, without any action required from the worker.

---

### 4. High-Distance Liability & Dynamic Travel Logistics

Long-distance bookings carry real risk — a worker traveling 40km for a low-value job is a reliability problem waiting to happen. The system addresses this explicitly.

- **Context-Aware Distance Thresholds:** Maximum acceptable travel distances are calibrated per job category. A cleaning job has a tight radius (e.g., 10km). A specialist consultant may have a threshold of 500km.
- **Automated Liability Warning:** If a booking crosses the optimal radius for the worker's trade, the customer receives a "High Distance Liability" alert before confirming — surfacing the risk of delays or no-shows transparently
- **Dynamic Travel Allowance (TA):** Travel compensation is calculated automatically based on actual distance, not a flat fee, ensuring workers are fairly compensated for longer trips

---

### 5. Bitwise Availability Engine

Worker scheduling uses bitwise arithmetic, not date-range queries.
When a booking is cancelled, the bits are restored atomically inside a Firestore transaction.

---

### 6. Transactional Integrity

All critical state transitions are wrapped in Firestore `@transactional` decorators:

- **Accept Booking:** Checks availability mask, assigns worker, expires all other pending requests for the same job — atomically
- **Cancel Booking:** Restores the worker's availability mask and cancels all pending worker requests
- **Submit Rating:** Updates global average rating and canonical-work-specific skill score in a single atomic write

## TODO: Native Language Support (Hindi & Regional Languages)

**Status:** Planning Phase  
**Priority:** High  
**Estimated Effort:** Medium-High

### Objective
Implement native language support for UI, SMS, and IVR to improve accessibility for workers who may not be fluent in English.

### Technical Requirements

#### 1. Flutter UI Internationalization
- Add `flutter_localizations` and ARB files for supported languages
- Implement language detection based on device locale
- Add language selection in user profile settings
- Support RTL languages if needed

#### 2. SMS Templates in Native Languages
- Create translated SMS templates for Hindi and major regional languages
- Implement language detection based on worker's location/state
- Handle variable substitution in translated text

#### 3. IVR Voice Prompts in Native Languages
- Create voice-friendly translations for IVR scripts
- Ensure proper pronunciation guides for TTS engines
- Test with actual TTS services

### Supported Languages
- Hindi (hi) - Primary
- Tamil (ta) - South India
- Telugu (te) - South India  
- Bengali (bn) - East India
- Gujarati (gu) - West India
- Marathi (mr) - West India
- Punjabi (pa) - North India

### Tasks
- [ ] Set up Flutter internationalization with ARB files
- [ ] Create translation dictionaries for SMS templates
- [ ] Implement language detection based on worker location
- [ ] Add IVR script translations with pronunciation guides
- [ ] Test TTS quality for each supported language
- [ ] Add language preference in user/worker profiles
- [ ] Implement fallback to English for unsupported content

---

## Getting Started

### Prerequisites

- Flutter SDK (stable channel)
- Python 3.9+
- Firebase project with Firestore and Authentication enabled
- Pinecone account (index with 1024 dimensions, `llama-text-embed-v2` model)
- Groq API key

### Flutter App

```sh
# Install dependencies
flutter pub get

# Run on device or emulator
flutter run

# Run in browser
flutter run -d chrome

# List connected devices
flutter devices

# Build release APK
flutter build apk

# Build App Bundle
flutter build appbundle
```

### Backend Server

```sh
# Install Python dependencies
pip install flask flask-cors firebase-admin python-dotenv requests

# Configure environment
cp .env.example .env
# Fill in: GROQ_API_KEY, PINECONE_API_KEY, PINECONE_INDEX_HOST, OTP_API_SECRET

# Add Firebase service account
# Place it at: firebase-service-account-key.json

# Start the server
python server.py
```

### Environment Variables

| Variable | Description |
|---|---|
| `GROQ_API_KEY` | Groq API key for LLM inference |
| `PINECONE_API_KEY` | Pinecone API key |
| `PINECONE_INDEX_HOST` | Full host URL of your Pinecone index |
| `OTP_API_SECRET` | Shared secret between Flutter app and backend |
| `MISSED_CALL_NO` | Fallback phone number for missed-call OTP |
| `TWILIO_ACCOUNT_SID` | Twilio account SID for SMS notifications |
| `TWILIO_AUTH_TOKEN` | Twilio auth token for SMS notifications |
| `TWILIO_PHONE_NUMBER` | Twilio phone number for sending SMS |
| `EXOTEL_API_KEY` | Exotel API key for IVR calls |
| `EXOTEL_API_TOKEN` | Exotel API token for IVR calls |
| `EXOTEL_SID` | Exotel account SID |
| `EXOTEL_CALLER_ID` | Exotel caller ID (virtual number) |
| `EXOTEL_APP_ID` | Exotel IVR flow/app ID |

---

## API Reference

All endpoints require the `x-secret-key` header.

| Endpoint | Method | Description |
|---|---|---|
| `/generate-otp` | POST | Initiate phone verification |
| `/verify-otp-log` | POST | Verify OTP and mark phone as confirmed |
| `/complete-signup` | POST | Create or update user/worker profile with AI skill processing |
| `/cw/predict-multi` | POST | AI extraction of multiple skills from a worker description |
| `/cw/predict` | POST | Single canonical work prediction from job text |
| `/tools/normalize` | POST | Normalize a raw tool name to its canonical form |
| `/create-booking` | POST | Create job request with smart matching and distance checks |
| `/worker-accept` | POST | Worker accepts a job (transactional) |
| `/worker-reject` | POST | Worker declines a job request |
| `/generate-start-otp` | POST | Generate OTP to confirm job start |
| `/verify-start-otp` | POST | Verify start OTP, transition job to in-progress |
| `/generate-end-otp` | POST | Generate OTP to confirm job completion |
| `/verify-end-otp` | POST | Verify end OTP, close job, update skill scores |
| `/submit-rating` | POST | Submit review with AI sentiment analysis and skill discovery |
| `/cancel-booking` | POST | Cancel booking and restore availability mask |
| `/get-worker-availability` | POST | Fetch available time slots for a worker on a given date |
| `/expire-requests` | POST | Expire stale pending worker requests (run via scheduler) |
| `/cron/process-escalations` | POST | Process notification escalations for job assignments and OTP deliveries (run every 5 mins via Google Cloud Scheduler) |

---

## Project Structure

```
kaarya/
├── lib/
│   ├── core/                        # Theme, API client
│   ├── features/
│   │   ├── auth/                    # Auth screen, worker onboarding, AI skill verification
│   │   ├── user/                    # Home, worker browse, booking creation, history
│   │   ├── worker/                  # Worker dashboard, job requests, calendar, SOS
│   │   └── shared/                  # Booking details, inbox, profile, rating/report dialogs
│   └── main.dart
├── backend/
│   ├── worker_matching.py           # Composite scoring and candidate ranking
│   ├── llm_functions.py             # Prompt engineering, skill extraction, profile healing
│   └── canonical_work.py           # Self-expanding canonical work and tool database
├── server.py                        # Flask entry point — routing and orchestration
├── lib/firebase.index.json          # Firestore composite indexes
└── README.md
```

---
## License

MIT

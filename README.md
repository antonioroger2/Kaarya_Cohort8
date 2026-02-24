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

No double-booking. No race conditions. No stale state.

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

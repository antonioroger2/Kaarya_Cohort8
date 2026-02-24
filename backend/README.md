# ⚙️ Kaarya Connect: Backend Engine

> **The intelligent routing and database management system powering Kaarya Connect.**
> This Python/Flask backend serves as the brain of the platform. It handles real-time semantic job matching, autonomous skill taxonomy generation, zero-trust OTP workflows, and bitwise availability scheduling.

## What Makes This Different

Most service APIs rely on rigid, hard-coded dropdown menus (e.g., `WHERE category == 'Plumber'`). Kaarya throws that out the window and uses **Llama 3.1 (via Groq) + Pinecone Vector DB** to handle data dynamically.

Here is what the AI is actually doing under the hood:

* **Zero-Dropdown Onboarding:** Workers write a plain-text summary of their experience. The LLM parses the paragraph and extracts a strict JSON object mapping their exact macro-skills and tools.
* **Smart Tool Normalization:** If a worker inputs *"Bosch GSB 500 RE Professional"*, the AI recognizes it, strips the brand/model, and normalizes it to the database standard: *"Power Drill"*.
* **Self-Building Database (Cold Starts):** If a customer requests a highly specific, never-before-seen job, the app doesn't fail. The LLM acts as an automated DBA—it generates a new "Canonical Work" category, determines the 5 essential tools needed for that job, and immediately upserts the new schema into Pinecone for future users. **The database builds and heals itself.**
* **Vector Matchmaking:** Customer requests are converted into vector embeddings. The backend calculates a composite score (Skill Match 60% + Global Rating 20% + Tool Availability 20%) comparing the semantic intent of the customer's problem against the worker's AI-parsed skill history.
* **✨ Autonomous Profile Healer:** When a customer submits a text review, the AI runs sentiment analysis to adjust the worker's rating dynamically. It also scans the text for "hidden skills" (e.g., *"he also fixed my doorbell"*). If found, the AI automatically verifies and injects the new skill into the worker's profile and Pinecone vectors.

---

## ⚡ Core Engineering Features

### 1. Concurrency & Data Integrity

Handling gig-worker bookings requires bulletproof state management to prevent double-booking. Critical endpoints like `accept_booking_in_transaction` and `cancel_booking_in_transaction` are wrapped in strict **Firestore `@transactional` decorators**.

### 2. Bitwise Time-Slot Availability

Instead of running heavy, slow database queries to check for schedule overlaps, the repo uses **bitwise masking**. A 24-hour day is stored as a single integer, and the system uses lightning-fast bitwise `AND`/`OR` operations to instantly check for schedule conflicts and lock slots.

### 3. Dual OTP-Secured Workflows

To build a "trustless" but highly secure platform, the API uses a strict OTP handshake. The job cannot transition to "In Progress" until the worker inputs the Start-OTP provided by the customer, and payment/completion cannot trigger without the End-OTP.

---

## 🛠 Tech Stack

| Component | Technology |
| --- | --- |
| **Framework** | Python 3.9+ / Flask / CORS |
| **Database** | Firebase Firestore (Admin SDK) |
| **Auth** | Firebase Authentication |
| **Vector DB** | Pinecone REST API (`llama-text-embed-v2`) |
| **LLM Inference** | Groq API (`Llama-3.1-8b-instant`) |

---

## 📂 Modular Architecture

The backend has been refactored for production-grade scalability, completely separating routing, transactional safety, and AI logic.

```text
backend/
├── routes/                 # Modular API endpoints
│   ├── routes_auth.py      # OTP handling and worker onboarding
│   └── routes_booking.py   # Job creation, OTP flow, and rating submission
├── ai_utils.py             # Raw Pinecone HTTP client & Groq requests
├── llm_functions.py        # Prompt engineering (Taxonomy & Profile Healer)
├── transactions.py         # Firestore @transactional safety wrappers
├── worker_matching.py      # Composite scoring & ranking algorithms
├── canonical_work.py       # Pinecone vector search and taxonomy generation
├── utils.py                # Bitwise masks, hashing, and sanitization
├── config.py               # Constants and environment variable mapping
└── main.py                 # Flask application entry point

```

---

## 🚀 Getting Started

### Prerequisites

* Python 3.9+
* Firebase service account key (`firebase-service-account-key.json`)
* Pinecone Index (1024 dimensions, Cosine metric)
* Groq API Key

### Installation

1. **Clone and Setup Virtual Environment:**
```sh
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

```


2. **Install Dependencies:**
```sh
pip install flask flask-cors firebase-admin python-dotenv requests

```


3. **Configure Environment:**
Create a `.env` file in the root directory:
```env
GROQ_API_KEY=your_groq_key_here
PINECONE_API_KEY=your_pinecone_key_here
PINECONE_INDEX_HOST=https://your-index-host.pinecone.io
OTP_API_SECRET=your_app_secret_key_here
PORT=5000

```


*Note: Ensure your `firebase-service-account-key.json` is placed in the root directory.*
4. **Run the Server:**
```sh
python main.py

```



---

## 📡 API Overview

*All requests must include the `x-secret-key` header.*

### Auth & Onboarding

* `POST /generate-otp` - Send verification OTP
* `POST /verify-otp-log` - Verify phone number
* `POST /complete-signup` - Creates user/worker and triggers AI profile parsing

### AI & Matching

* `POST /cw/predict-multi` - AI extraction of hierarchical skills from unstructured text
* `POST /cw/predict` - Standardizes a raw job request into a Canonical Work vector
* `POST /tools/normalize` - Strips brand names and returns macro-level tool definitions

### Jobs & Transactions

* `POST /create-booking` - Triggers the Vector Search & Composite Scoring algorithm
* `POST /worker-accept` - Transactional assignment with bitwise slot locking
* `POST /generate-start-otp` & `/verify-start-otp` - Job initiation handshake
* `POST /generate-end-otp` & `/verify-end-otp` - Job completion handshake
* `POST /submit-rating` - Triggers the **Autonomous Profile Healer** AI loop

---
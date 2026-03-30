# routes_booking.py
from flask import request, jsonify
from datetime import datetime, timezone, timedelta
import uuid
import json
import re
import urllib.parse
from collections import defaultdict
import numpy as np
import requests
from ..firebase_init import db
from ..constants import COL_BOOKINGS, COL_WORKERS, COL_CW, COL_OTP, COL_CATEGORIES
from ..utils import require_secret, sanitize_phone, gen_otp, hash_code, now_ts
from ..config import FULL_MASK
from ..canonical_work import get_or_create_global_canonical_work
from ..worker_matching import get_best_workers_for_job
from ..transactions import cancel_booking_in_transaction, accept_booking_in_transaction, submit_rating_healer_transaction
from ..llm_functions import llm_analyze_review
from google.cloud.firestore import FieldFilter
from google.cloud.firestore_v1.transforms import Increment


def _extract_json_object(raw):
    text = str(raw).strip()
    if "```json" in text:
        text = text.split("```json", 1)[1].rsplit("```", 1)[0].strip()
    elif "```" in text:
        text = text.split("```", 1)[1].rsplit("```", 1)[0].strip()
    try:
        return json.loads(text)
    except Exception:
        return {}


def _clean_words(text):
    return {w for w in re.split(r"[^a-z0-9]+", str(text).lower()) if w}


def _keyword_overlap_score(user_query: str, meta: dict) -> float:
    query_words = _clean_words(user_query)
    if not query_words:
        return 0.0

    name_words = _clean_words(meta.get("category", ""))
    cw_words = _clean_words(meta.get("canonicalWork", meta.get("name", "")))
    tools_words: set[str] = set()
    for tool in meta.get("requiredTools", []) or []:
        tools_words |= _clean_words(tool)
    desc_words = _clean_words(meta.get("description", ""))

    weighted_score = (
        len(query_words.intersection(name_words)) * 1.0
        + len(query_words.intersection(cw_words)) * 1.0
        + len(query_words.intersection(tools_words)) * 0.7
        + len(query_words.intersection(desc_words)) * 0.6
    )

    return weighted_score / len(query_words)


def _geocode_with_nominatim(locality: str, pin: str):
    query = f"{locality} {pin} India".strip()
    if not query:
        return None

    url = "https://nominatim.openstreetmap.org/search"
    params = {
        "q": query,
        "format": "json",
        "limit": 1,
    }

    headers = {"User-Agent": "KaaryaBackend/1.0"}

    try:
        resp = requests.get(url, params=params, headers=headers, timeout=8)
        if resp.status_code != 200:
            return None
        data = resp.json()
        if not data:
            return None
        lat = float(data[0].get("lat")) if data[0].get("lat") else None
        lon = float(data[0].get("lon")) if data[0].get("lon") else None
        if lat is None or lon is None:
            return None
        return lat, lon
    except Exception as e:
        print(f"[GEOCODE] error: {e}")
        return None

def register_booking_routes(app):
    @app.route("/cw/predict-multi", methods=["POST"])
    @require_secret
    def predict_multi_skills():
        data = request.json
        text = data.get("text")

        if not text:
            return jsonify({"error": "text required"}), 400

        from ..canonical_work import process_worker_profile

        try:
            cw_list = process_worker_profile(text)
        except Exception as e:
            print(f"[predict-multi] Error: {e}")
            return jsonify({"error": str(e)}), 500

        results = []
        seen = set()

        for cw_data in cw_list:
            key = cw_data.get("cw_id")
            if not key or key in seen:
                continue
            seen.add(key)

            results.append({
                "category":                    cw_data["category"],
                "task":                        cw_data["canonicalWork"],
                "cw_id":                       cw_data["cw_id"],
                "suggestedTools":              cw_data.get("requiredTools", []),
                "aiSuggestedToolsFromProfile": cw_data.get("requiredTools", []),
            })

        return jsonify({"predictions": results}), 200

    @app.route("/cw/predict", methods=["POST"])
    @require_secret
    def predict_canonical_work():
        data = request.json
        text = data.get("text")
        user_pincode = data.get("pincode")

        if not text:
            return jsonify({"error": "text required"}), 400

        from ..ai_utils import pinecone_embed_text, pinecone_query, run_llm
        from ..llm_functions import (
            llm_select_best_match,
            extract_and_classify_profile,
            batch_judge_cw_candidates,
            judge_category_match,
        )

        try:
            # 1) Local constraints (optional)
            local_services: set[str] = set()
            if user_pincode:
                local_workers = (
                    db.collection(COL_WORKERS)
                    .where(filter=FieldFilter("pincode", "==", user_pincode))
                    .where(filter=FieldFilter("isActive", "==", True))
                    .stream()
                )
                for worker in local_workers:
                    cw_data_map = worker.to_dict().get("cw_data", {}) or {}
                    for _, task_map in cw_data_map.items():
                        if not isinstance(task_map, dict):
                            continue
                        for _, cw_info in task_map.items():
                            name = cw_info.get("name")
                            if name:
                                local_services.add(str(name).lower())

            top_k_recall = 40
            max_rerank = 10
            W1 = 0.25  # Pinecone weight
            W2 = 0.65  # LLM weight (intentionally high)

            print(f"[/cw/predict] text='{text[:200]}' local_filter={'on' if local_services else 'off'}")

            primary_cat = None
            primary_task = None
            try:
                profile = extract_and_classify_profile(text)
                jobs = profile.get("jobs", []) or []
                if jobs:
                    primary_cat = jobs[0].get("category")
                    primary_task = jobs[0].get("task")
            except Exception as e:
                print(f"[predict] profile extract fallback: {e}")

            embedding = pinecone_embed_text(text)
            base_filter = {"type": "job"}
            pinecone_candidates = pinecone_query(embedding, top_k=top_k_recall, filter_dict=base_filter)
            print(f"[/cw/predict] base candidates: {len(pinecone_candidates)}")

            # Local post-filter on pinecone results if pincode provided
            if user_pincode and local_services:
                filtered_candidates = []
                for cand in pinecone_candidates:
                    cand_task = (cand.get("metadata", {}) or {}).get("canonicalWork", "") or (cand.get("metadata", {}) or {}).get("name", "")
                    if str(cand_task).lower() in local_services:
                        filtered_candidates.append(cand)
                if filtered_candidates:
                    pinecone_candidates = filtered_candidates
                print(f"[/cw/predict] after local filter: {len(pinecone_candidates)}")

            # Category-first recall to cut cross-trade bleed
            cat_filter = None
            if primary_cat:
                cat_emb = pinecone_embed_text(primary_cat)
                cat_matches = pinecone_query(cat_emb, top_k=10, filter_dict={"type": "category"})
                match_id = judge_category_match(primary_cat, cat_matches)
                if match_id:
                    cat_doc = db.collection(COL_CATEGORIES).document(match_id).get().to_dict()
                    if cat_doc:
                        cat_filter = {"type": "job", "category_id": cat_doc.get("category_id")}

            if cat_filter:
                job_query_text = f"{primary_cat} {primary_task}" if primary_task else text
                pinecone_candidates.extend(pinecone_query(pinecone_embed_text(job_query_text), top_k=25, filter_dict=cat_filter))
                pinecone_candidates.extend(pinecone_query(pinecone_embed_text(text), top_k=15, filter_dict=cat_filter))
                print(f"[/cw/predict] cat-filter applied; total candidates now {len(pinecone_candidates)}")

            # Group by (category, canonicalWork) and keep top 2 from each
            grouped: dict[tuple[str, str], list] = defaultdict(list)
            for cand in pinecone_candidates:
                meta = cand.get("metadata", {}) or {}
                key = (meta.get("category", ""), meta.get("canonicalWork", meta.get("name", "")))
                grouped[key].append(cand)

            deduped = []
            for items in grouped.values():
                deduped.extend(sorted(items, key=lambda x: x.get("score", 0), reverse=True)[:2])

            deduped = sorted(deduped, key=lambda x: x.get("score", 0), reverse=True)[:max_rerank]

            if not deduped:
                print("[/cw/predict] deduped empty -> 404")
                return jsonify({"error": "No canonical work available"}), 404

            # LLM rerank with explicit scoring output
            lines = []
            for idx, cand in enumerate(deduped):
                meta = cand.get("metadata", {}) or {}
                lines.append(
                    f"{idx+1}. ID:{cand.get('id')} | Category:{meta.get('category','?')} | Task:{meta.get('canonicalWork', meta.get('name','?'))} | Desc:{meta.get('description','')[:180]}"
                )

            prompt = f"""
User request: "{text}"
Candidates:
{chr(10).join(lines)}
Score each candidate from 0.0 to 1.0 for how well it matches. Return ONLY JSON object mapping index to score. Higher = better.
"""
            raw_scores = run_llm(prompt, max_new_tokens=200)
            llm_scores = _extract_json_object(raw_scores)

            scored = []
            llm_score_map = {}
            for idx, cand in enumerate(deduped, start=1):
                meta = cand.get("metadata", {}) or {}
                pine_score_raw = float(cand.get("score", 0.0))
                pine_score = float(np.tanh(pine_score_raw))  # squash any large similarity values
                llm_score = float(llm_scores.get(str(idx), 0.0) or llm_scores.get(idx, 0.0) or 0.0)
                overlap = _keyword_overlap_score(text, meta)
                total = (W1 * pine_score) + (W2 * llm_score) + overlap
                llm_score_map[cand.get("id")] = llm_score
                scored.append((total, cand))

            scored.sort(key=lambda x: x[0], reverse=True)
            winner = scored[0][1]
            winner_doc = db.collection(COL_CW).document(winner.get("id")).get().to_dict()

            if not winner_doc:
                print(f"[/cw/predict] winner_doc missing for id {winner.get('id')}")
                return jsonify({"error": "No canonical work available"}), 404

            return jsonify({
                "category": winner_doc["category"],
                "task": winner_doc["canonicalWork"],
                "cw_id": winner_doc["cw_id"],
                "suggestedTools": winner_doc.get("requiredTools", []),
                "_debug": {
                    "pinecone_score": winner.get("score", 0.0),
                    "llm_score": llm_score_map.get(winner.get("id"), 0.0),
                    "overlap_score": _keyword_overlap_score(text, winner_doc),
                },
            }), 200

        except Exception as e:
            print(f"Predict CW Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/tools/normalize", methods=["POST"])
    @require_secret
    def normalize_tool():
        data = request.json
        tool_input = data.get("toolName")

        if not tool_input:
            return jsonify({"error": "toolName required"}), 400

        from ..canonical_work import get_or_create_canonical_tool

        try:
            normalized = get_or_create_canonical_tool(tool_input)

            if "LLM_ERROR" in normalized or "LLM_DISABLED" in normalized:
                 return jsonify({"error": "Tool normalization failed"}), 500

            return jsonify({"original": tool_input, "normalized": normalized}), 200
        except Exception as e:
            print(f"Normalize Tool Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/workers/geocode", methods=["POST"])
    @require_secret
    def geocode_worker():
        data = request.json or {}
        worker_id = data.get("workerId")
        pin = (data.get("pincode") or "").strip()
        locality = (data.get("locality") or "").strip()

        if not worker_id:
            return jsonify({"error": "workerId required"}), 400
        if not pin:
            return jsonify({"error": "pincode required"}), 400

        geo = _geocode_with_nominatim(locality, pin)
        if not geo:
            return jsonify({"error": "Geocoding failed"}), 502

        lat, lon = geo

        try:
            db.collection(COL_WORKERS).document(worker_id).update({
                "lat": lat,
                "lon": lon,
            })
            return jsonify({"ok": True, "lat": lat, "lon": lon}), 200
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    @app.route("/create-booking", methods=["POST"])
    @require_secret
    def create_booking():
        data = request.json
        user_id = data.get("userId")
        candidate_workers_input = data.get("candidateWorkers", [])

        # Normalize location fields coming from nested payloads
        loc = data.get("location") or {}
        if isinstance(loc, dict):
            data["pincode"] = data.get("pincode") or loc.get("pin") or loc.get("pincode")
            data["lat"] = data.get("lat") or loc.get("lat") or loc.get("latitude")
            data["lon"] = data.get("lon") or loc.get("lng") or loc.get("lon") or loc.get("longitude")
            # Keep address-ish fields if needed later
            data.setdefault("location", loc)

        notes = data.get("notes", "")
        service_type = data.get("serviceType", "General").strip()
        service_category = data.get("serviceCategory", "General").strip()
        required_tools = data.get("requiredTools", []) or []

        # 1. ADD FLAG TO TRACK IF AI WAS USED
        is_ai_booking = False

        if not candidate_workers_input:
            is_ai_booking = True  # Tag as AI generated because no workers were manually provided
            
            if len(notes) < 20:
                print(f"[AI BOOKING] Reject: short notes ({len(notes)} chars)")
                return jsonify({"error": "Notes too short or no candidates provided"}), 400

            user_pincode = data.get("pincode")
            if not user_pincode:
                print(f"[AI BOOKING] Reject: missing pincode. Payload keys: {list(data.keys())}")
                return jsonify({"error": "Location/Pincode is required for Smart AI Booking"}), 400

            # --- 1. GET LOCAL INVENTORY (FieldFilter to avoid deprecation) ---
            local_workers = (
                db.collection(COL_WORKERS)
                .where(filter=FieldFilter("pincode", "==", user_pincode))
                .where(filter=FieldFilter("isActive", "==", True))
                .stream()
            )

            available_services: dict[str, str] = {}  # lower -> original
            available_service_meta: dict[str, dict] = {}
            worker_count = 0

            for worker in local_workers:
                worker_count += 1
                w_data = worker.to_dict()
                cw_data_map = w_data.get("cw_data", {}) or {}

                # cw_data is stored as {category: {task_slug: info}} so flatten nested entries
                for _, task_map in cw_data_map.items():
                    if not isinstance(task_map, dict):
                        continue
                    for _, cw_info in task_map.items():
                        cat = cw_info.get("category")
                        name = cw_info.get("name")
                        if cat and name:
                            key = str(name).lower()
                            available_services[key] = name
                            available_service_meta[key] = cw_info

            print(f"[/create-booking] pincode={user_pincode} available_workers={worker_count} unique_services={len(available_services)}")

            if not available_services:
                return jsonify({"error": "There are no workers currently available in your area."}), 400

            # --- 2. VECTOR SEARCH & LOCAL POST-FILTERING ---
            from ..ai_utils import pinecone_embed_text, pinecone_query
            from ..llm_functions import run_llm

            embedding = pinecone_embed_text(notes)
            pinecone_candidates = pinecone_query(embedding, top_k=40, filter_dict={"type": "job"})

            local_matches = []
            seen_tasks = set()

            for cand in pinecone_candidates:
                meta = cand.get("metadata", {}) or {}
                cand_task = meta.get("canonicalWork", meta.get("name", ""))
                cand_task_lower = str(cand_task).lower()

                if cand_task_lower in available_services and cand_task_lower not in seen_tasks:
                    seen_tasks.add(cand_task_lower)
                    local_matches.append(cand)

            local_matches = local_matches[:10]

            if not local_matches:
                return jsonify({"error": "No workers available - We do not have professionals for this specific category in your area."}), 400

            top_pinecone_match = local_matches[0].get('metadata', {}).get('canonicalWork', 'Unknown')

            # --- 3. STRICT LLM RERANKING ---
            service_menu = "\n".join([
                f"- Task: '{cand.get('metadata', {}).get('canonicalWork')}' (Category: '{cand.get('metadata', {}).get('category')}')" 
                for cand in local_matches
            ])

            prompt = f"""
            You are an intelligent dispatch routing engine.
            User Request: "{notes}"
            
            Top Local Semantic Matches:
            {service_menu}

            Task: Find the single best 'Task' from the list that perfectly fulfills the User Request. 
            
            CRITICAL BOUNDARY RULES:
            1. SYNONYMS ARE VALID: If the user asks for "babysit" and "Child Care" is available, this is a PERFECT match. Select it.
            2. UNRELATED TRADES ARE INVALID: If the user asks for "babysit" and the only available services are "Tap Repair" or "Wiring", this is a FAIL. Do NOT force a bad match. You MUST return null.
            3. DOMAIN STRICTNESS: Do not assign a plumber to watch kids. Do not assign a housekeeper to fix electrical panels. 
            
            You MUST output ONLY a valid JSON object. 
            Schema: {{
                "best_task": "string or null", 
                "best_category": "string or null",
                "reasoning": "A 1-sentence explanation of why you matched these, or why you returned null."
            }}
            """

            raw_response = run_llm(prompt, max_new_tokens=150)
            llm_choice = _extract_json_object(raw_response)

            matched_task = llm_choice.get("best_task")
            matched_task_lower = str(matched_task).lower() if matched_task else ""
            reasoning = llm_choice.get("reasoning", "")
            
            print(f"[AI ROUTING] Decision: {matched_task} | Reason: {reasoning}")

            if not matched_task or matched_task_lower == "null" or matched_task_lower not in available_services:
                return jsonify({
                    "error": f"No workers available - Best Match '{top_pinecone_match}' is not the perfect described category."
                }), 400

            real_matched_task = available_services[matched_task_lower]

            service_type = real_matched_task
            service_category = llm_choice.get("best_category") or available_service_meta.get(matched_task_lower, {}).get("category")
            required_tools = available_service_meta.get(matched_task_lower, {}).get("requiredTools", []) or []

            data["serviceType"] = service_type
            data["serviceCategory"] = service_category
            data["requiredTools"] = required_tools

        final_candidates = candidate_workers_input
        if not final_candidates:
            best_workers = get_best_workers_for_job(
                cw_name=service_type,
                cw_category=service_category,
                required_tools=required_tools,
                top_k=10,
                pincode=data.get("pincode"),
                lat=data.get("lat"),
                lon=data.get("lon"),
            )
            final_candidates = [w["workerId"] for w in best_workers]
            data["candidateWorkersDetails"] = best_workers

        if not final_candidates:
            return jsonify({"error": "No suitable workers found for this specific request in your area."}), 400

        try:
            date_str = data["date"]
            start_hour = int(data["startHour"])
            end_hour = int(data["endHour"])
            wage = int(data["wage"])
            hours = end_hour - start_hour

            dt_obj = datetime.strptime(date_str, "%Y-%m-%d")
            appt_dt = dt_obj.replace(hour=start_hour, minute=0, second=0, tzinfo=timezone.utc)

            booking_ref = db.collection(COL_BOOKINGS).document()
            booking_id = booking_ref.id
            now_ts_val = now_ts()

            # 2. ADD AI METADATA TO THE DB OBJECT
            booking_obj = {
                "userId": user_id,
                "userPhone": sanitize_phone(data.get("userPhone")),
                "workerId": None,
                "status": "b1",
                "date": date_str,
                "appointmentDate": appt_dt,
                "startHour": start_hour,
                "endHour": end_hour,
                "serviceType": service_type,
                "serviceCategory": service_category,
                "wage": wage,
                "notes": notes,
                "location": data.get("location"),
                "candidateWorkers": final_candidates,
                "isAIGenerated": is_ai_booking,                # <--- AI Flag
                "requestedWorkerCount": len(final_candidates), # <--- Worker Count
                "createdAt": now_ts_val,
                "updatedAt": now_ts_val,
            }

            batch = db.batch()
            batch.set(booking_ref, booking_obj)

            for wid in final_candidates:
                req_ref = booking_ref.collection("workerRequests").document(wid)
                batch.set(req_ref, {
                    "workerId": wid,
                    "status": "pending",
                    "createdAt": now_ts_val,
                    "updatedAt": now_ts_val
                })

            batch.update(booking_ref, {"status": "b2"})
            batch.commit()

            return jsonify({"ok": True, "bookingId": booking_id, "matched": len(final_candidates)}), 200

        except Exception as e:
            print(f"Booking creation error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/worker-accept", methods=["POST"])
    @require_secret
    def worker_accept():
        data = request.json
        wid = data["workerId"]
        bid = data["bookingId"]
        b_ref = db.collection(COL_BOOKINGS).document(bid)

        try:
            transaction = db.transaction()
            accept_booking_in_transaction(
                transaction,
                b_ref,
                b_ref.collection("workerRequests").document(wid),
                wid
            )

            # After successful acceptance, trigger initial push notification for job assignment
            # This is part of the escalation protocol - Level 1 (immediate push)
            from ..notifications import escalate_job_assignment
            escalate_job_assignment(bid, wid, 1)  # Level 1 = Push notification

            # Update escalation tracking
            db.collection(COL_BOOKINGS).document(bid).update({
                "lastEscalationLevel": 1,
                "lastEscalationAt": now_ts(),
                "updatedAt": now_ts()
            })

            return jsonify({"ok": True}), 200
        except Exception as e:
            error_msg = str(e)
            print(f"Worker Accept Error: {error_msg}")

            if "WORKER_NOT_AVAILABLE" in error_msg:
                return jsonify({"error": "Worker not available at this time"}), 400

            return jsonify({"error": error_msg}), 500

    @app.route("/worker-reject", methods=["POST"])
    @require_secret
    def worker_reject():
        data = request.json
        wid = data["workerId"]
        bid = data["bookingId"]

        try:
            db.collection(COL_BOOKINGS)\
                .document(bid)\
                .collection("workerRequests")\
                .document(wid)\
                .update({"status": "rejected", "updatedAt": now_ts()})
            return jsonify({"ok": True}), 200
        except Exception as e:
            print(f"Worker Reject Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/generate-start-otp", methods=["POST"])
    @require_secret
    def generate_start_otp():
        data = request.json
        bid = data["bookingId"]

        try:
            booking_snap = db.collection(COL_BOOKINGS).document(bid).get()
            if not booking_snap.exists:
                return jsonify({"error": "Booking not found"}), 404
            booking = booking_snap.to_dict()

            if booking.get("status") not in ("a1", "w1"):
                return jsonify({"error": "Invalid booking status"}), 400

            worker_id = booking["workerId"]
            w_doc_snap = db.collection(COL_WORKERS).document(worker_id).get()
            if not w_doc_snap.exists:
                return jsonify({"error": "Worker not found"}), 404
            w_doc = w_doc_snap.to_dict()

            w_phone = sanitize_phone(w_doc.get("phone"))
            if not w_phone:
                return jsonify({"error": "Worker phone not found"}), 400

            code = gen_otp(6)
            cid = str(uuid.uuid4())

            # Store OTP in database with escalation tracking
            db.collection(COL_OTP).document(w_phone).set({
                "hash": hash_code(code),
                "correlation_id": cid,
                "expires_at": int((datetime.now(timezone.utc) + timedelta(minutes=15)).timestamp()),
                "bookingId": bid,
                "otpType": "start",
                "escalationEnabled": True,
                "lastEscalationLevel": 0,  # Will be set to 1 after initial push
                "lastEscalationAt": None
            })

            batch = db.batch()
            b_ref = db.collection(COL_BOOKINGS).document(bid)
            batch.update(b_ref, {
                "status": "w1",
                "startOTPCorrelationId": cid
            })

            batch.set(b_ref.collection("otpEvents").document(cid), {
                "type": "start",
                "otpHash": hash_code(code),
                "verified": False,
                "generatedAt": now_ts(),
                "escalationTracking": {
                    "enabled": True,
                    "lastLevel": 0,
                    "lastAt": None
                }
            })
            batch.commit()

            # Trigger initial push notification for Start-OTP (Level 1 of escalation)
            from ..notifications import escalate_otp_delivery
            escalate_otp_delivery(bid, worker_id, "start", code, 1)

            # Update escalation tracking
            db.collection(COL_OTP).document(w_phone).update({
                "lastEscalationLevel": 1,
                "lastEscalationAt": now_ts()
            })

            return jsonify({"ok": True, "correlationId": cid, "otp": code}), 200

        except Exception as e:
            print(f"Generate Start OTP Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/verify-start-otp", methods=["POST"])
    @require_secret
    def verify_start_otp():
        data = request.json
        bid = data["bookingId"]
        cid = data["correlationId"]
        code = data["code"]
        b_ref = db.collection(COL_BOOKINGS).document(bid)

        evt_ref = b_ref.collection("otpEvents").document(cid)
        evt = evt_ref.get()

        if not evt.exists:
            return jsonify({"error": "OTP event not found"}), 404

        evt_data = evt.to_dict()

        if evt_data.get("verified", False):
            return jsonify({"error": "OTP already verified"}), 400

        if hash_code(code) == evt_data["otpHash"]:
            batch = db.batch()
            batch.update(evt_ref, {"verified": True, "verifiedAt": now_ts()})
            batch.update(b_ref, {
                "status": "w2",
                "workStartedAt": now_ts()
            })
            batch.commit()

            return jsonify({"ok": True}), 200

        return jsonify({"valid": False, "error": "Invalid code"}), 400

    @app.route("/generate-end-otp", methods=["POST"])
    @require_secret
    def generate_end_otp():
        data = request.json
        bid = data["bookingId"]

        try:
            booking_snap = db.collection(COL_BOOKINGS).document(bid).get()
            if not booking_snap.exists:
                return jsonify({"error": "Booking not found"}), 404
            booking = booking_snap.to_dict()

            if booking.get("status") != "w2":
                return jsonify({"error": "Job not started"}), 400

            worker_id = booking.get("workerId")
            if not worker_id:
                return jsonify({"error": "Worker not found"}), 404

            worker_doc_snap = db.collection(COL_WORKERS).document(worker_id).get()
            if not worker_doc_snap.exists:
                return jsonify({"error": "Worker not found"}), 404
            w_doc = worker_doc_snap.to_dict()

            w_phone = sanitize_phone(w_doc.get("phone"))
            if not w_phone:
                return jsonify({"error": "Worker phone not found"}), 400

            code = gen_otp(6)
            cid = str(uuid.uuid4())

            # Store OTP in database with escalation tracking
            db.collection(COL_OTP).document(w_phone).set({
                "hash": hash_code(code),
                "correlation_id": cid,
                "expires_at": int((datetime.now(timezone.utc) + timedelta(minutes=15)).timestamp()),
                "bookingId": bid,
                "otpType": "end",
                "escalationEnabled": True,
                "lastEscalationLevel": 0,  # Will be set to 1 after initial push
                "lastEscalationAt": None
            })

            batch = db.batch()
            b_ref = db.collection(COL_BOOKINGS).document(bid)
            batch.update(b_ref, {
                "status": "e1",
                "endOTPCorrelationId": cid
            })

            batch.set(b_ref.collection("otpEvents").document(cid), {
                "type": "end",
                "otpHash": hash_code(code),
                "verified": False,
                "generatedAt": now_ts(),
                "escalationTracking": {
                    "enabled": True,
                    "lastLevel": 0,
                    "lastAt": None
                }
            })
            batch.commit()

            # Trigger initial push notification for End-OTP (Level 1 of escalation)
            from ..notifications import escalate_otp_delivery
            escalate_otp_delivery(bid, worker_id, "end", code, 1)

            # Update escalation tracking
            db.collection(COL_OTP).document(w_phone).update({
                "lastEscalationLevel": 1,
                "lastEscalationAt": now_ts()
            })

            return jsonify({"ok": True, "correlationId": cid, "otp": code}), 200
        except Exception as e:
            print(f"Generate End OTP Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/verify-end-otp", methods=["POST"])
    @require_secret
    def verify_end_otp():
        data = request.json
        bid = data["bookingId"]
        cid = data["correlationId"]
        code = data["code"]

        b_ref = db.collection(COL_BOOKINGS).document(bid)
        evt_ref = b_ref.collection("otpEvents").document(cid)
        evt = evt_ref.get()

        if not evt.exists:
            return jsonify({"error": "OTP event not found"}), 404

        evt_data = evt.to_dict()

        if hash_code(code) == evt_data["otpHash"]:
            if evt_data.get("verified", False):
                return jsonify({"error": "OTP already verified"}), 400

            evt_ref.update({"verified": True, "verifiedAt": now_ts()})

            booking = b_ref.get().to_dict()
            worker_id = booking["workerId"]
            cw_name = booking.get("serviceType", "General")

            cw_id = None
            try:
                cw_docs = db.collection(COL_CW).where(filter=FieldFilter("canonicalWork", "==", cw_name)).limit(1).stream()
                for doc in cw_docs:
                    cw_id = doc.id
                    break
            except Exception as e:
                print(f"Error finding CW: {e}")

            now_ts_val = now_ts()

            b_ref.update({
                "status": "e3",
                "completedAt": now_ts_val,
                "updatedAt": now_ts_val,
                "payment.status": "paid" if data.get("paymentReceived") else "pending"
            })

            w_ref = db.collection(COL_WORKERS).document(worker_id)
            w_ref.update({"completedBookings": Increment(1), "updatedAt": now_ts_val})

            try:
                if cw_id:
                    db.collection(COL_CW).document(cw_id).update({"totalJobsGlobal": Increment(1)})
            except Exception as e:
                print(f"Error updating CW stats: {e}")

            return jsonify({"ok": True}), 200

        return jsonify({"valid": False, "error": "Invalid code"}), 400

    @app.route("/submit-rating", methods=["POST"])
    @require_secret
    def submit_rating():
        data = request.json
        bid = data["bookingId"]
        raw_rating = float(data["rating"])
        worker_id = data["workerId"]
        user_id = data["userId"]
        review = data.get("review", "").strip()

        b_ref = db.collection(COL_BOOKINGS).document(bid)
        w_ref = db.collection(COL_WORKERS).document(worker_id)

        try:
            # Pre-Transaction: Run the Profile Healer Pipeline
            adjusted_rating = raw_rating
            prof_score = raw_rating
            canonical_new_skills = []

            if len(review) > 15: # Only run AI on meaningful text reviews
                booking_doc = b_ref.get().to_dict()
                primary_job = booking_doc.get("serviceType", "General Repair")
                
                # 1. Analyze text for sentiment & hidden skills
                adj_r, p_score, hidden_skills = llm_analyze_review(review, raw_rating, primary_job)
                adjusted_rating = adj_r
                prof_score = p_score
                
                # 2. Canonicalize discovered skills using EXISTING Pinecone pipeline
                for skill in hidden_skills:
                    cat = skill.get("category", "General")
                    task = skill.get("task")
                    if task:
                        print(f"✨ Profile Healer Discovered New Skill: {task} for worker {worker_id}")
                        # This generates vectors and upserts if it's completely new!
                        cw_data = get_or_create_global_canonical_work(cat, task)
                        if cw_data:
                            canonical_new_skills.append(cw_data)

            # Execute Transaction
            transaction = db.transaction()
            submit_rating_healer_transaction(
                transaction,
                b_ref,
                w_ref,
                user_id,
                raw_rating,
                adjusted_rating,
                prof_score,
                review,
                canonical_new_skills
            )
            return jsonify({"ok": True, "healer_triggered": len(canonical_new_skills) > 0}), 200
            
        except Exception as e:
            print(f"Submit Rating Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/cancel-booking", methods=["POST"])
    @require_secret
    def cancel_booking():
        data = request.json
        booking_id = data.get("bookingId")
        user_id = data.get("userId")
        reason = data.get("reason", "User requested cancellation")

        try:
            booking_ref = db.collection(COL_BOOKINGS).document(booking_id)

            transaction = db.transaction()
            cancel_booking_in_transaction(transaction, booking_ref, user_id, reason)

            reqs = booking_ref.collection("workerRequests")\
                .where(filter=FieldFilter("status", "==", "pending")).stream()
            batch = db.batch()
            has_updates = False
            now_ts_val = now_ts()

            for r in reqs:
                batch.update(r.reference, {"status": "expired", "updatedAt": now_ts_val})
                has_updates = True

            if has_updates:
                batch.commit()

            return jsonify({"ok": True}), 200
        except Exception as e:
            print(f"Cancel Booking Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/get-booking/<bookingId>", methods=["GET"])
    @require_secret
    def get_booking(bookingId):
        try:
            b = db.collection(COL_BOOKINGS).document(bookingId).get()
            if not b.exists:
                return jsonify({"error": "Booking not found"}), 404

            doc = b.to_dict()
            reqs = [r.to_dict() for r in b.reference.collection("workerRequests").stream()]
            otps = [o.to_dict() for o in b.reference.collection("otpEvents").stream()]

            doc["workerRequests"] = reqs
            doc["otpEvents"] = otps
            return jsonify(doc), 200
        except Exception as e:
            print(f"Get Booking Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/get-worker-availability", methods=["POST"])
    @require_secret
    def get_worker_availability():
        data = request.json
        wid = data["workerId"]
        date_id = data["date"]

        avail_doc = db.collection(COL_WORKERS).document(wid)\
            .collection("availability").document(date_id).get()

        current_mask = FULL_MASK
        if avail_doc.exists:
            current_mask = int(avail_doc.to_dict().get("mask", FULL_MASK))

        available_hours = []
        for i in range(24):
            if (current_mask >> i) & 1:
                available_hours.append(i)

        return jsonify({"ok": True, "availableHours": available_hours}), 200

    @app.route("/cron/process-escalations", methods=["POST"])
    @require_secret
    def process_escalations():
        """
        Cron endpoint to process notification escalations for job assignments and OTP deliveries.
        Should be called every 5 minutes via Google Cloud Scheduler.

        Checks for:
        1. Job assignments pending worker acceptance (>10min, >20min, >30min)
        2. OTP deliveries that haven't been acknowledged (>10min, >20min)
        """
        try:
            now = datetime.now(timezone.utc)
            now_ts_val = now_ts()

            # Process job assignment escalations
            job_escalation_count = 0

            # Query for bookings in "b2" status (pending worker acceptance)
            q = db.collection(COL_BOOKINGS).where(filter=FieldFilter("status", "==", "b2")).stream()

            for booking_doc in q:
                booking_data = booking_doc.to_dict()
                booking_id = booking_doc.id
                created_at = booking_data.get("createdAt")

                if not created_at:
                    continue

                # Calculate time elapsed since booking creation
                if isinstance(created_at, datetime):
                    elapsed_minutes = (now - created_at).total_seconds() / 60
                else:
                    continue

                # Get assigned worker
                assigned_worker = booking_data.get("assignedWorker")
                if not assigned_worker:
                    continue

                # Determine escalation level based on elapsed time
                escalation_level = None
                if elapsed_minutes >= 30:
                    # Level 4: Expire the job
                    db.collection(COL_BOOKINGS).document(booking_id).update({
                        "status": "expired",
                        "updatedAt": now_ts_val,
                        "expiredReason": "timeout_no_acceptance",
                        "expiredAt": now_ts_val
                    })
                    print(f"[ESCALATION] Job {booking_id} expired after {elapsed_minutes:.1f} minutes")
                    job_escalation_count += 1
                    continue
                elif elapsed_minutes >= 20:
                    escalation_level = 3  # IVR Call
                elif elapsed_minutes >= 10:
                    escalation_level = 2  # SMS
                elif elapsed_minutes >= 0:
                    escalation_level = 1  # Push (initial)

                if escalation_level:
                    # Check if this level has already been sent
                    last_escalation = booking_data.get("lastEscalationLevel", 0)
                    if escalation_level > last_escalation:
                        from ..notifications import escalate_job_assignment
                        escalate_job_assignment(booking_id, assigned_worker, escalation_level)

                        # Update the booking with new escalation level
                        db.collection(COL_BOOKINGS).document(booking_id).update({
                            "lastEscalationLevel": escalation_level,
                            "lastEscalationAt": now_ts_val,
                            "updatedAt": now_ts_val
                        })
                        job_escalation_count += 1
                        print(f"[ESCALATION] Job {booking_id} escalated to level {escalation_level} after {elapsed_minutes:.1f} minutes")

            # Process OTP delivery escalations
            otp_escalation_count = 0

            # Query for active OTP records that haven't been verified
            otp_query = db.collection(COL_OTP).where(filter=FieldFilter("escalationEnabled", "==", True)).stream()

            for otp_doc in otp_query:
                otp_data = otp_doc.to_dict()
                phone = otp_doc.id
                booking_id = otp_data.get("bookingId")
                otp_type = otp_data.get("otpType")
                last_level = otp_data.get("lastEscalationLevel", 0)
                last_at = otp_data.get("lastEscalationAt")

                if not booking_id or not otp_type:
                    continue

                # Check if OTP is still valid (not expired and not verified)
                expires_at = otp_data.get("expires_at")
                if expires_at and datetime.fromtimestamp(expires_at, timezone.utc) < now:
                    continue  # OTP expired

                # Check if booking still needs this OTP
                booking_doc = db.collection(COL_BOOKINGS).document(booking_id).get()
                if not booking_doc.exists:
                    continue
                booking_data = booking_doc.to_dict()

                # Check if OTP has been verified already
                correlation_id = otp_data.get("correlation_id")
                if correlation_id:
                    otp_event = booking_doc.reference.collection("otpEvents").document(correlation_id).get()
                    if otp_event.exists and otp_event.to_dict().get("verified", False):
                        continue  # Already verified

                # Calculate time since last escalation
                elapsed_minutes = 0
                if last_at and isinstance(last_at, datetime):
                    elapsed_minutes = (now - last_at).total_seconds() / 60
                elif last_level == 0:
                    # First escalation - check from OTP creation time
                    # For simplicity, assume we escalate after 10, 20 minutes
                    elapsed_minutes = 15  # Force escalation for pending OTPs

                # Determine escalation level
                escalation_level = None
                if elapsed_minutes >= 20 and last_level < 3:
                    escalation_level = 3  # IVR Call
                elif elapsed_minutes >= 10 and last_level < 2:
                    escalation_level = 2  # SMS

                if escalation_level:
                    # Get worker ID from booking
                    worker_id = booking_data.get("assignedWorker") or booking_data.get("workerId")
                    if worker_id:
                        # Get the OTP code (we need to retrieve it)
                        # This is a limitation - we should store the plain OTP for escalation
                        # For now, we'll skip actual OTP escalation and just log
                        print(f"[OTP ESCALATION] Would escalate {otp_type} OTP for booking {booking_id} to level {escalation_level}")

                        # TODO: Store plain OTP code for escalation purposes
                        # For production, we'd need to store the plain OTP temporarily

                        # Update escalation tracking
                        db.collection(COL_OTP).document(phone).update({
                            "lastEscalationLevel": escalation_level,
                            "lastEscalationAt": now_ts_val
                        })
                        otp_escalation_count += 1

            return jsonify({
                "ok": True,
                "jobEscalations": job_escalation_count,
                "otpEscalations": otp_escalation_count,
                "timestamp": now.isoformat()
            }), 200

        except Exception as e:
            print(f"Process Escalations Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/expire-requests", methods=["POST"])
    @require_secret
    def expire_requests():
        data = request.json or {}
        older = int(data.get("olderThanSeconds", 3600))
        cutoff_dt = datetime.now(timezone.utc) - timedelta(seconds=older)
        now_ts_val = now_ts()

        try:
            q = db.collection(COL_BOOKINGS).where(filter=FieldFilter("status", "==", "b2")).stream()
            updated_count = 0
            batch = db.batch()

            for b in q:
                reqs = b.reference.collection("workerRequests").where(filter=FieldFilter("status", "==", "pending")).stream()
                for r in reqs:
                    r_data = r.to_dict()
                    if r_data.get("createdAt") and r_data["createdAt"] < cutoff_dt:
                        batch.update(r.reference, {"status": "expired", "updatedAt": now_ts_val})
                        updated_count += 1

            if updated_count > 0:
                 batch.commit()

            return jsonify({"ok": True, "expiredCount": updated_count}), 200
        except Exception as e:
            print(f"Expire Requests Error: {e}")
            return jsonify({"error": str(e)}), 500
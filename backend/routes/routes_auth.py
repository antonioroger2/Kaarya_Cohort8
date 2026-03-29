# routes_auth.py
from flask import request, jsonify
from firebase_admin import auth
import uuid
from datetime import datetime, timedelta, timezone
from ..firebase_init import db
from ..constants import COL_OTP, COL_VERIFIED
from ..utils import require_secret, sanitize_phone, gen_otp, hash_code, now_ts, slugify
from ..config import API_SECRET, EMAIL_SUFFIX

def _handle_auth_creation(uid, password, name):
    try:
        auth.create_user(
            uid=uid,
            email=f"{uid}{EMAIL_SUFFIX}",
            password=password,
            display_name=name
        )
        return True, None
    except auth.EmailAlreadyExistsError:
        # This is not an error in our case, just means the user exists
        return True, None
    except auth.UidAlreadyExistsError:
        return True, None
    except Exception as e:
        return False, str(e)

def register_auth_routes(app):
    @app.route("/generate-otp", methods=["POST"])
    def generate_otp():
        secret = request.headers.get("x-secret-key")
        if secret != API_SECRET:
            return jsonify({"error": "Unauthorized"}), 401

        phone = request.json.get("phone")
        if not phone:
            return jsonify({"error": "Phone required"}), 400

        sanitized = sanitize_phone(phone)
        code = gen_otp(6)
        cid = str(uuid.uuid4())
        expires = int((datetime.now(timezone.utc) + timedelta(minutes=5)).timestamp())

        try:
            db.collection(COL_OTP).document(sanitized).set({
                "hash": hash_code(code),
                "correlation_id": cid,
                "expires_at": expires,
                "sim_message": {"text": f"{code} is your OTP verification code."}
            })
            return jsonify({"ok": True, "correlation_id": cid}), 200
        except Exception as e:
            print(f"Generate OTP Error: {e}")
            return jsonify({"error": str(e)}), 500

    @app.route("/verify-otp-log", methods=["POST"])
    def verify_otp_log():
        secret = request.headers.get("x-secret-key")
        if secret != API_SECRET:
            return jsonify({"error": "Unauthorized"}), 401

        data = request.json
        phone = sanitize_phone(data.get("phone"))
        code = data.get("code")
        cid = data.get("correlation_id")

        doc_ref = db.collection(COL_OTP).document(phone)
        doc = doc_ref.get()
        if not doc.exists:
            return jsonify({"valid": False, "error": "Expired"}), 400

        rec = doc.to_dict()
        if rec['hash'] != hash_code(code) or rec['correlation_id'] != cid:
            return jsonify({"valid": False, "error": "Invalid Code"}), 400

        db.collection(COL_VERIFIED).document(phone).set({
            "phone": phone,
            "correlation_id": cid,
            "verified_at": now_ts(),
            "status": "verified"
        })
        doc_ref.delete()
        return jsonify({"valid": True}), 200

    @app.route("/complete-signup", methods=["POST"])
    @require_secret
    def complete_signup():
        from ..canonical_work import get_or_create_global_canonical_work
        from ..llm_functions import analyze_worker_profile_hierarchical

        if db is None:
            return jsonify({"error": "Database not initialized"}), 503

        try:
            data = request.json
            phone = sanitize_phone(data.get("phone"))
            password = data.get("password")
            name = data.get("name")
            is_worker = data.get("isWorker", False)

            uid = phone
            coll = "workers" if is_worker else "users"
            doc_ref = db.collection(coll).document(uid)
            worker_exists = doc_ref.get().exists

            try:
                hourly = int(data.get("hourlyRate", 300))
            except (ValueError, TypeError):
                hourly = 300

            if not worker_exists:
                # Temporarily disabled OTP verification for development
                # if not db.collection(COL_VERIFIED).document(phone).get().exists:
                #     return jsonify({"error": "Phone not verified"}), 400

                if not password:
                    return jsonify({"error": "Password required"}), 400

                auth_ok, auth_err = _handle_auth_creation(uid, password, name)
                if not auth_ok:
                    return jsonify({"error": auth_err}), 500

                # db.collection(COL_VERIFIED).document(phone).delete()  # Also disable deletion

                base_profile_updates = {
                    "uid": uid,
                    "phone": phone,
                    "name": name,
                    "pincode": data.get("pin"),
                    "locality": data.get("locality"),
                    "role": "worker" if is_worker else "user",
                    "createdAt": now_ts(),
                    "isActive": True,
                    "updatedAt": now_ts()
                }

                if not is_worker:
                    doc_ref.set(base_profile_updates, merge=True)
                    return jsonify({"ok": True}), 200

            verified_skills_payload = data.get("verifiedSkills", [])

            all_canonical_tools = set()
            cw_data_to_save = {}
            cw_skill_score = {}
            all_canonical_works = []
            tool_normalization_cache = {}

            for skill_entry in verified_skills_payload:
                raw_tools_for_skill = skill_entry.get("myTools", [])
                for raw_tool_str in raw_tools_for_skill:
                    if str(raw_tool_str).strip() in tool_normalization_cache:
                        continue
                    from .canonical_work import get_or_create_canonical_tool
                    canonical_tool = get_or_create_canonical_tool(str(raw_tool_str).strip())
                    if canonical_tool:
                        tool_normalization_cache[str(raw_tool_str).strip()] = canonical_tool
                        all_canonical_tools.add(canonical_tool)

            for skill_entry in verified_skills_payload:
                task = skill_entry.get("task", "General Task").strip()
                category = skill_entry.get("category", "General").strip()
                raw_tools_for_task = skill_entry.get("myTools", [])

                cw_doc_data = get_or_create_global_canonical_work(category, task)

                task_name_std = cw_doc_data['canonicalWork']
                category_name_std = cw_doc_data['category']

                all_canonical_works.append(task_name_std)
                task_slug = slugify(task_name_std)

                canonical_tools_for_task = [
                    tool_normalization_cache[str(t).strip()]
                    for t in raw_tools_for_task
                    if str(t).strip() in tool_normalization_cache
                ]

                if category_name_std not in cw_data_to_save:
                    cw_data_to_save[category_name_std] = {}

                cw_data_to_save[category_name_std][task_slug] = {
                    "name": task_name_std,
                    "category": category_name_std,
                    "tools": list(set(canonical_tools_for_task)),
                    "rating": 5.0,
                    "total_works": 0
                }

                if task_name_std not in cw_skill_score:
                    cw_skill_score[task_name_std] = {"score": 5.0, "jobsCompleted": 0}

            worker_update_data = {
                "name": name,
                "pincode": data.get("pin"),
                "locality": data.get("locality"),
                "perHourCharge": hourly,
                "toolsAvailable": list(all_canonical_tools),
                "canonicalWorks": list(set(all_canonical_works)),
                "cwSkillScore": cw_skill_score,
                "cw_data": cw_data_to_save,
                "profileDescription": data.get("profileDescription"),
                "updatedAt": now_ts(),
            }

            if not worker_exists:
                worker_update_data.update({
                    "avgRating": 5.0,
                    "completedBookings": 0,
                    "availability": "Y",
                    **base_profile_updates,
                })
                doc_ref.set(worker_update_data, merge=True)
                return jsonify({"ok": True}), 200
            else:
                doc_ref.update(worker_update_data)
                return jsonify({"ok": True}), 200

        except Exception as e:
            print(f"Signup/Update Error for {uid}: {e}")
            return jsonify({"error": str(e)}), 500
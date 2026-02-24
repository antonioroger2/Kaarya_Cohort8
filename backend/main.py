# main.py
from flask import Flask
from flask_cors import CORS
from .firebase_init import db  # Ensure Firebase is initialized
from .routes.routes_auth import register_auth_routes
from .routes.routes_booking import register_booking_routes

app = Flask(__name__)
CORS(app)

# Register all route modules
register_auth_routes(app)
register_booking_routes(app)

@app.route("/", methods=["GET"])
def health_check():
    return {"status": "healthy"}, 200

if __name__ == "__main__":
    import os
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
import logging
import os
import time
import datetime

from flask import Flask, jsonify

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

app = Flask(__name__)

ALLOC_MB = int(os.getenv("ALLOC_MB", "100"))
APP_NAME = os.getenv("APP_NAME", "memory-lab-app")

logger.info("APP=%s  ALLOC_MB=%d  started=%sZ", APP_NAME, ALLOC_MB, datetime.datetime.utcnow().isoformat())

memory_holder: list[bytearray] = []

for i in range(ALLOC_MB):
    memory_holder.append(bytearray(1024 * 1024))
    time.sleep(0.01)
    if (i + 1) % 10 == 0:
        logger.info("allocated %d / %d MB", i + 1, ALLOC_MB)

STARTUP_TIME = datetime.datetime.utcnow().isoformat() + "Z"
logger.info("startup complete: %d MB held at %s", ALLOC_MB, STARTUP_TIME)

request_count = 0
error_count = 0


@app.route("/health")
def health():
    return jsonify({
        "status": "ok",
        "app": APP_NAME,
        "alloc_mb": ALLOC_MB,
        "startup_time": STARTUP_TIME,
        "request_count": request_count,
    }), 200


@app.route("/ping")
def ping():
    return "pong", 200


@app.route("/")
def root():
    return jsonify({"app": APP_NAME, "alloc_mb": ALLOC_MB, "uptime_since": STARTUP_TIME}), 200


@app.route("/stats")
def stats():
    return jsonify({
        "app": APP_NAME,
        "alloc_mb": ALLOC_MB,
        "startup_time": STARTUP_TIME,
        "memory_chunks": len(memory_holder),
        "request_count": request_count,
        "error_count": error_count,
        "now": datetime.datetime.utcnow().isoformat() + "Z",
    }), 200


@app.before_request
def before():
    global request_count
    request_count += 1


@app.after_request
def after(response):
    if response.status_code >= 500:
        global error_count
        error_count += 1
        logger.warning("5xx response: %d", response.status_code)
    return response


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)

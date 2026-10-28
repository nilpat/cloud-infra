import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)

APP_VERSION = os.environ.get("APP_VERSION", "v1")
# Populated from SSM Parameter Store in the "secrets" exercise (step 6 in the
# README). Until then it is simply absent, which is the point.
APP_GREETING = os.environ.get("APP_GREETING", "<not injected yet>")


@app.get("/")
def index():
    return jsonify(
        version=APP_VERSION,
        greeting=APP_GREETING,
        # ECS gives each Fargate task its own ENI, so this changes per task.
        # Refresh the ALB URL a few times and you will see it flip between
        # the running tasks -- that is your proof that load balancing works.
        served_by=socket.gethostname(),
        task_arn=_task_arn(),
    )


@app.get("/health")
def health():
    """Target group + container health check hit this."""
    return jsonify(status="ok"), 200


@app.get("/crash")
def crash():
    """Deliberately kill the worker, so you can watch ECS replace the task."""
    os._exit(1)


def _task_arn():
    """ECS injects a metadata endpoint; cheap way to show which task answered."""
    uri = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
    if not uri:
        return "not running on ECS"
    try:
        import json
        import urllib.request

        with urllib.request.urlopen(f"{uri}/task", timeout=1) as r:
            return json.load(r).get("TaskARN", "unknown")
    except Exception as exc:  # noqa: BLE001 - lab code, surface the reason
        return f"metadata lookup failed: {exc}"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))

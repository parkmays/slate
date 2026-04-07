import json
import urllib.request

BRIDGE_BASE = "http://127.0.0.1:8544"


def fetch_json(path: str):
    req = urllib.request.Request(f"{BRIDGE_BASE}{path}", method="GET")
    with urllib.request.urlopen(req, timeout=3) as res:
        return json.loads(res.read().decode("utf-8"))


def list_projects():
    return fetch_json("/api/nle/projects")


def list_clips(project_id: str | None = None):
    query = f"?projectId={project_id}" if project_id else ""
    return fetch_json(f"/api/nle/clips{query}")


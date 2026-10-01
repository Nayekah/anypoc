#!/usr/bin/env python3
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


BASE = "http://127.0.0.1:8080"
REALM = "anypoc"
CLIENT_ID = "resource-server-test"
CLIENT_SECRET = "secret"
TOKEN_URL = f"{BASE}/realms/{REALM}/protocol/openid-connect/token"
PROTECTION = f"{BASE}/realms/{REALM}/authz/protection"


def post_form(url, fields, bearer=None):
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    if bearer:
        req.add_header("Authorization", f"Bearer {bearer}")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def post_json(url, payload, bearer):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {bearer}")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def token(grant_fields):
    status, body = post_form(TOKEN_URL, grant_fields)
    print("token_status", status)
    print(body)
    if status != 200:
        raise SystemExit(1)
    return json.loads(body)["access_token"]


def create_resource(service_token, name, owner):
    status, body = post_json(
        f"{PROTECTION}/resource_set",
        {
            "name": name,
            "owner": owner,
            "ownerManagedAccess": True,
            "scopes": [{"name": "Scope A"}, {"name": "Scope B"}, {"name": "Scope C"}],
        },
        service_token,
    )
    print("create_resource_status", owner, status)
    print(body)
    if status != 201:
        raise SystemExit(1)
    parsed = json.loads(body)
    return parsed.get("_id") or parsed.get("id")


def main():
    suffix = f"{int(time.time())}"
    service_token = token(
        {
            "grant_type": "client_credentials",
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
        }
    )
    marta_token = token(
        {
            "grant_type": "password",
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "username": "marta",
            "password": "password",
        }
    )
    marta_id = create_resource(service_token, f"PoC Marta {suffix}", "marta")
    kolo_id = create_resource(service_token, f"PoC Kolo {suffix}", "kolo")
    print("marta_resource", marta_id)
    print("kolo_resource", kolo_id)

    status, body = post_form(
        TOKEN_URL,
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "audience": CLIENT_ID,
            "permission": f"{kolo_id}#Scope A",
        },
        marta_token,
    )
    print("pre_auth", status, body)

    status, body = post_json(
        f"{PROTECTION}/uma-policy/{marta_id}",
        {
            "name": f"cross-resource-{suffix}",
            "resources": [kolo_id],
            "scopes": ["Scope A"],
            "users": ["marta"],
        },
        marta_token,
    )
    print("policy_create", status, body)

    status, body = post_form(
        TOKEN_URL,
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "audience": CLIENT_ID,
            "permission": f"{kolo_id}#Scope A",
        },
        marta_token,
    )
    print("post_auth", status, body)


if __name__ == "__main__":
    main()

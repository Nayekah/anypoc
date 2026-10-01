#!/usr/bin/env python3
import json
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:8080"
REALM = "anypoc"
TOKEN = f"{BASE}/realms/{REALM}/protocol/openid-connect/token"
PROTECTION = f"{BASE}/realms/{REALM}/authz/protection"
CLIENT_ID = "resource-server-test"
CLIENT_SECRET = "secret"


def request(method, url, data=None, headers=None):
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(url, data=body, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        try:
            return e.code, json.loads(txt)
        except Exception:
            return e.code, {"raw": txt}


def token(user, password):
    status, body = form(TOKEN, {
        "grant_type": "password",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "username": user,
        "password": password,
    })
    print("token", user, status, body.keys())
    return body.get("access_token")


for user in ("marta", "kolo"):
    access = token(user, "password")
    if not access:
        continue
    payload = {
        "name": f"probe {user} {int(time.time())}",
        "ownerManagedAccess": True,
        "scopes": [{"name": "Scope A"}, {"name": "Scope B"}, {"name": "Scope C"}],
    }
    status, body = request("POST", f"{PROTECTION}/resource_set", payload, {"Authorization": f"Bearer {access}"})
    print("create", user, status, body[:500])

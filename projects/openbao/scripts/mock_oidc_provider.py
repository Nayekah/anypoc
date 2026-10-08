#!/usr/bin/env python3
"""Minimal local OIDC discovery service for the disposable AnyPoC lab."""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlparse


HOST = "127.0.0.1"
PORT = 9001
ISSUER = f"http://{HOST}:{PORT}"


class Handler(BaseHTTPRequestHandler):
    server_version = "AnyPoC-OIDC/1.0"

    def log_message(self, fmt, *args):
        print(f"[mock-oidc] {self.address_string()} {fmt % args}", flush=True)

    def send_json(self, status, value):
        body = json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/.well-known/openid-configuration":
            self.send_json(
                200,
                {
                    "issuer": ISSUER,
                    "authorization_endpoint": f"{ISSUER}/authorize",
                    "token_endpoint": f"{ISSUER}/token",
                    "jwks_uri": f"{ISSUER}/jwks",
                    "response_types_supported": ["code"],
                    "subject_types_supported": ["public"],
                    "id_token_signing_alg_values_supported": ["RS256"],
                    "scopes_supported": ["openid", "profile"],
                    "token_endpoint_auth_methods_supported": ["client_secret_post"],
                    "claims_supported": ["sub"],
                },
            )
            return

        if parsed.path == "/jwks":
            self.send_json(200, {"keys": []})
            return

        if parsed.path == "/authorize":
            query = parse_qs(parsed.query)
            redirect_uri = query.get("redirect_uri", [""])[0]
            state = query.get("state", [""])[0]
            if not redirect_uri:
                self.send_json(400, {"error": "invalid_request"})
                return
            separator = "&" if "?" in redirect_uri else "?"
            location = redirect_uri + separator + urlencode(
                {"state": state, "error_description": "Local identity provider denied the request."}
            )
            self.send_response(302)
            self.send_header("Location", location)
            self.end_headers()
            return

        if parsed.path == "/health":
            self.send_json(200, {"status": "ok"})
            return

        self.send_json(404, {"error": "not_found"})

    def do_POST(self):
        if urlparse(self.path).path == "/token":
            self.send_json(400, {"error": "access_denied"})
            return
        self.send_json(404, {"error": "not_found"})


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()

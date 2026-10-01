#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[seed-keycloak] %s %s\n' "$(date +%H:%M:%S)" "$*"
}

BASE_URL=${BASE_URL:-http://127.0.0.1:8080}
REALM=anypoc
ADMIN_USER=admin
ADMIN_PASS=adminpass
RESOURCE_CLIENT=resource-server-test
RESOURCE_SECRET=secret
ATTACKER_USER=marta
ATTACKER_PASS=password
VICTIM_USER=kolo
VICTIM_PASS=password
SEED_FILE=/opt/keycloak-data/seed-info.json
KCADM=/opt/keycloak/bin/kcadm.sh

for _ in $(seq 1 60); do
    if curl -fsS "${BASE_URL}/health/ready" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

"$KCADM" config credentials --server "$BASE_URL" --realm master --user "$ADMIN_USER" --password "$ADMIN_PASS" >/dev/null

if ! "$KCADM" get "realms/${REALM}" >/dev/null 2>&1; then
    log "Creating realm ${REALM}"
    "$KCADM" create realms -s realm="$REALM" -s enabled=true >/dev/null
fi

for role in uma_authorization uma_protection role_a role_b role_c role_d; do
    if ! "$KCADM" get "roles/${role}" -r "$REALM" >/dev/null 2>&1; then
        "$KCADM" create roles -r "$REALM" -s name="$role" >/dev/null
    fi
done

ensure_user() {
    local username=$1
    local password=$2

    if ! "$KCADM" get users -r "$REALM" -q "username=${username}" | jq -e 'length > 0' >/dev/null; then
        "$KCADM" create users -r "$REALM" -s username="$username" -s enabled=true >/dev/null
    fi

    "$KCADM" set-password -r "$REALM" --username "$username" --new-password "$password" >/dev/null
}

ensure_user "$ATTACKER_USER" "$ATTACKER_PASS"
ensure_user "$VICTIM_USER" "$VICTIM_PASS"

if ! "$KCADM" get clients -r "$REALM" -q "clientId=${RESOURCE_CLIENT}" | jq -e 'length > 0' >/dev/null; then
    log "Creating client ${RESOURCE_CLIENT}"
    "$KCADM" create clients -r "$REALM" \
        -s clientId="$RESOURCE_CLIENT" \
        -s enabled=true \
        -s publicClient=false \
        -s secret="$RESOURCE_SECRET" \
        -s directAccessGrantsEnabled=true \
        -s serviceAccountsEnabled=true \
        -s authorizationServicesEnabled=true \
        -s 'redirectUris=["http://127.0.0.1:8081/*"]' \
        >/dev/null
fi

if ! "$KCADM" get clients -r "$REALM" -q 'clientId=client-a' | jq -e 'length > 0' >/dev/null; then
    "$KCADM" create clients -r "$REALM" \
        -s clientId=client-a \
        -s enabled=true \
        -s publicClient=true \
        -s 'redirectUris=["http://127.0.0.1:8081/*"]' \
        >/dev/null
fi

CLIENT_UUID=$("$KCADM" get clients -r "$REALM" -q "clientId=${RESOURCE_CLIENT}" | jq -r '.[0].id')

if ! "$KCADM" get "clients/${CLIENT_UUID}/roles/uma_protection" -r "$REALM" >/dev/null 2>&1; then
    "$KCADM" create "clients/${CLIENT_UUID}/roles" -r "$REALM" -s name=uma_protection >/dev/null
fi

"$KCADM" add-roles -r "$REALM" --uusername "$ATTACKER_USER" --rolename uma_authorization --rolename uma_protection >/dev/null 2>&1 || true
"$KCADM" add-roles -r "$REALM" --uusername "$VICTIM_USER" --rolename role_a >/dev/null 2>&1 || true
"$KCADM" add-roles -r "$REALM" --uusername "$ATTACKER_USER" --cclientid "$RESOURCE_CLIENT" --rolename uma_protection >/dev/null 2>&1 || true

TOKEN_ENDPOINT="${BASE_URL}/realms/${REALM}/protocol/openid-connect/token"
PROTECTION_BASE="${BASE_URL}/realms/${REALM}/authz/protection"

SERVICE_TOKEN=$(curl -fsS \
    -d grant_type=client_credentials \
    -d client_id="$RESOURCE_CLIENT" \
    -d client_secret="$RESOURCE_SECRET" \
    "$TOKEN_ENDPOINT" | jq -r '.access_token')

create_resource() {
    local name=$1
    local owner=$2
    local marker=$3
    local payload
    local response

    payload=$(jq -nc \
        --arg name "$name" \
        --arg owner "$owner" \
        --arg marker "$marker" \
        '{
            name: $name,
            owner: $owner,
            ownerManagedAccess: true,
            scopes: [
                {name: "Scope A"},
                {name: "Scope B"},
                {name: "Scope C"}
            ],
            attributes: {
                anypoc_marker: [$marker]
            }
        }')

    response=$(curl -fsS \
        -H "Authorization: Bearer ${SERVICE_TOKEN}" \
        -H 'Content-Type: application/json' \
        -d "$payload" \
        "${PROTECTION_BASE}/resource_set")

    printf '%s' "$response"
}

extract_resource_id() {
    jq -r '._id // .id // .resourceId // empty'
}

ATTACKER_RESOURCE_JSON=$(create_resource "ANYPOC Marta Resource" "$ATTACKER_USER" "attack-surface")
VICTIM_RESOURCE_JSON=$(create_resource "ANYPOC Kolo Resource" "$VICTIM_USER" "victim-target")

ATTACKER_RESOURCE_ID=$(printf '%s' "$ATTACKER_RESOURCE_JSON" | extract_resource_id)
VICTIM_RESOURCE_ID=$(printf '%s' "$VICTIM_RESOURCE_JSON" | extract_resource_id)

if [ -z "$ATTACKER_RESOURCE_ID" ] || [ -z "$VICTIM_RESOURCE_ID" ]; then
    log "Failed to create seeded resources"
    printf 'attacker_resource_json=%s\n' "$ATTACKER_RESOURCE_JSON"
    printf 'victim_resource_json=%s\n' "$VICTIM_RESOURCE_JSON"
    exit 1
fi

jq -nc \
    --arg realm "$REALM" \
    --arg base_url "$BASE_URL" \
    --arg client_id "$RESOURCE_CLIENT" \
    --arg client_secret "$RESOURCE_SECRET" \
    --arg attacker_user "$ATTACKER_USER" \
    --arg attacker_pass "$ATTACKER_PASS" \
    --arg attacker_resource_id "$ATTACKER_RESOURCE_ID" \
    --arg attacker_resource_name "ANYPOC Marta Resource" \
    --arg victim_user "$VICTIM_USER" \
    --arg victim_pass "$VICTIM_PASS" \
    --arg victim_resource_id "$VICTIM_RESOURCE_ID" \
    --arg victim_resource_name "ANYPOC Kolo Resource" \
    '{
        realm: $realm,
        base_url: $base_url,
        token_endpoint: ($base_url + "/realms/" + $realm + "/protocol/openid-connect/token"),
        client: {
            client_id: $client_id,
            client_secret: $client_secret
        },
        attacker: {
            username: $attacker_user,
            password: $attacker_pass,
            resource_id: $attacker_resource_id,
            resource_name: $attacker_resource_name
        },
        victim: {
            username: $victim_user,
            password: $victim_pass,
            resource_id: $victim_resource_id,
            resource_name: $victim_resource_name
        },
        scopes: ["Scope A", "Scope B", "Scope C"]
    }' > "$SEED_FILE"

log "Seed complete: attacker_resource_id=${ATTACKER_RESOURCE_ID} victim_resource_id=${VICTIM_RESOURCE_ID}"

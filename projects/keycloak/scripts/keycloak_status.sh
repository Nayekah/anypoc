#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${1:-http://127.0.0.1:8080}
READY_URL=${READY_URL:-http://127.0.0.1:9000/health/ready}
REALM_URL="${BASE_URL%/}/realms/anypoc/.well-known/openid-configuration"
SEED_FILE=/opt/keycloak-data/seed-info.json

printf 'ready_url=%s\n' "$READY_URL"
printf 'realm_url=%s\n' "$REALM_URL"

ready_status=$(curl -s -o /tmp/keycloak-ready.out -w '%{http_code}' "$READY_URL" || true)
realm_status=$(curl -s -o /tmp/keycloak-realm.out -w '%{http_code}' "$REALM_URL" || true)

printf 'ready_status=%s\n' "$ready_status"
printf 'realm_status=%s\n' "$realm_status"

if [ -f "$SEED_FILE" ]; then
    printf 'seed_file=%s\n' "$SEED_FILE"
    jq -r '.realm as $realm | .attacker.username as $attacker | .victim.username as $victim | "seed_realm=\($realm)\nseed_attacker=\($attacker)\nseed_victim=\($victim)\nattacker_resource_id=\(.attacker.resource_id)\nvictim_resource_id=\(.victim.resource_id)"' "$SEED_FILE"
else
    printf 'seed_file=missing\n'
fi

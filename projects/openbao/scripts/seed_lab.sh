#!/usr/bin/env bash
set -euo pipefail

export BAO_ADDR=http://127.0.0.1:8200
export BAO_TOKEN=root

AUTH_PATH=oidc
ROLE_NAME=lab-direct
OIDC_ISSUER=http://127.0.0.1:9001
REDIRECT_URI=http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback
SEED_FILE=/opt/openbao-data/seed-info.json

if ! bao auth list -format=json | jq -e 'has("oidc/")' >/dev/null; then
    bao auth enable -path="$AUTH_PATH" jwt >/dev/null
fi

bao write "auth/${AUTH_PATH}/config" \
    oidc_discovery_url="$OIDC_ISSUER" \
    oidc_client_id=anypoc-client \
    oidc_client_secret=anypoc-secret \
    default_role="$ROLE_NAME" \
    >/dev/null

bao write "auth/${AUTH_PATH}/role/${ROLE_NAME}" \
    role_type=oidc \
    user_claim=sub \
    allowed_redirect_uris="$REDIRECT_URI" \
    callback_mode=direct \
    token_policies=default \
    >/dev/null

jq -n \
    --arg address "$BAO_ADDR" \
    --arg auth_path "$AUTH_PATH" \
    --arg role "$ROLE_NAME" \
    --arg issuer "$OIDC_ISSUER" \
    --arg redirect_uri "$REDIRECT_URI" \
    '{
        address: $address,
        auth_path: $auth_path,
        role: $role,
        oidc_issuer: $issuer,
        redirect_uri: $redirect_uri
    }' > "$SEED_FILE"

printf '[seed-openbao] ready: auth_path=%s role=%s\n' "$AUTH_PATH" "$ROLE_NAME"

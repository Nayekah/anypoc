#!/usr/bin/env bash
set -euo pipefail

OPENBAO_URL=http://127.0.0.1:8200/v1/sys/health
OIDC_URL=http://127.0.0.1:9001/health

openbao_status=$(curl -sS -o /tmp/openbao-health.json -w '%{http_code}' "$OPENBAO_URL" || true)
oidc_status=$(curl -sS -o /tmp/openbao-oidc-health.json -w '%{http_code}' "$OIDC_URL" || true)

printf 'openbao_http_status=%s\n' "$openbao_status"
printf 'oidc_http_status=%s\n' "$oidc_status"

if [ "$openbao_status" != "200" ] || [ "$oidc_status" != "200" ]; then
    exit 1
fi

/usr/local/bin/bao version

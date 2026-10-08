#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[openbao-services] %s %s\n' "$(date +%H:%M:%S)" "$*"
}

DATA_DIR=/opt/openbao-data
LOG_DIR=/var/log/openbao
SERVER_LOG="$LOG_DIR/server.log"
OIDC_LOG="$LOG_DIR/oidc-provider.log"
SERVER_PID=/tmp/openbao-server.pid
OIDC_PID=/tmp/openbao-oidc.pid

install -d -m 775 -o playground -g playground "$DATA_DIR" "$LOG_DIR"
install -m 664 -o playground -g playground /dev/null "$SERVER_LOG"
install -m 664 -o playground -g playground /dev/null "$OIDC_LOG"

if [ ! -f "$OIDC_PID" ] || ! kill -0 "$(cat "$OIDC_PID")" 2>/dev/null; then
    log "Starting local OIDC provider"
    runuser -u playground -- bash -lc "
        nohup python3 /opt/openbao-lab/scripts/mock_oidc_provider.py > '$OIDC_LOG' 2>&1 &
        echo \$! > '$OIDC_PID'
    "
fi

for _ in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:9001/health >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! curl -fsS http://127.0.0.1:9001/health >/dev/null 2>&1; then
    log "OIDC provider failed to become ready"
    tail -n 100 "$OIDC_LOG" || true
    exit 1
fi

if [ ! -f "$SERVER_PID" ] || ! kill -0 "$(cat "$SERVER_PID")" 2>/dev/null; then
    log "Starting OpenBao dev server"
    runuser -u playground -- bash -lc "
        export BAO_ADDR=http://127.0.0.1:8200
        nohup /usr/local/bin/bao server -dev \
            -dev-root-token-id=root \
            -dev-listen-address=127.0.0.1:8200 \
            -dev-no-store-token > '$SERVER_LOG' 2>&1 &
        echo \$! > '$SERVER_PID'
    "
fi

for _ in $(seq 1 120); do
    if curl -fsS http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! curl -fsS http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
    log "OpenBao failed to become ready"
    tail -n 200 "$SERVER_LOG" || true
    exit 1
fi

log "Seeding local authentication lab"
runuser -u playground -- /opt/openbao-lab/scripts/seed_lab.sh

#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[keycloak-services] %s %s\n' "$(date +%H:%M:%S)" "$*"
}

KEYCLOAK_HOME=/opt/keycloak
DATA_DIR=/opt/keycloak-data
LOG_DIR=/var/log/keycloak
LOG_FILE="$LOG_DIR/server.log"
PID_FILE=/tmp/keycloak.pid
READY_URL=http://127.0.0.1:9000/health/ready

install -d -m 775 -o playground -g playground "$DATA_DIR" "$LOG_DIR"
install -m 664 -o playground -g playground /dev/null "$LOG_FILE"

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "Starting Keycloak dev server"
    runuser -u playground -- bash -lc "
        export KC_BOOTSTRAP_ADMIN_USERNAME=admin
        export KC_BOOTSTRAP_ADMIN_PASSWORD=adminpass
        export KC_DB=dev-file
        export KC_HTTP_ENABLED=true
        export KC_HTTP_PORT=8080
        export KC_HEALTH_ENABLED=true
        export KC_METRICS_ENABLED=false
        export KC_HOSTNAME_STRICT=false
        export KC_PROXY_HEADERS=xforwarded
        export KC_SPI_THEME_CACHE_THEMES=false
        export KC_SPI_THEME_CACHE_TEMPLATES=false
        export KC_SPI_THEME_STATIC_MAX_AGE=-1
        nohup \"$KEYCLOAK_HOME/bin/kc.sh\" start-dev --http-port=8080 --hostname-strict=false --http-enabled=true --health-enabled=true > \"$LOG_FILE\" 2>&1 &
        echo \$! > \"$PID_FILE\"
    "
fi

for _ in $(seq 1 120); do
    if curl -fsS "$READY_URL" >/dev/null 2>&1; then
        log "Keycloak is ready"
        break
    fi
    sleep 2
done

if ! curl -fsS "$READY_URL" >/dev/null 2>&1; then
    log "Keycloak failed to become ready"
    tail -n 200 "$LOG_FILE" || true
    exit 1
fi

log "Seeding lab realm"
runuser -u playground -- /opt/keycloak-lab/scripts/seed_lab.sh

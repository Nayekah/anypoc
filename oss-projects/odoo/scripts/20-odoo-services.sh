#!/bin/bash
set -euo pipefail

cluster_line="$(pg_lsclusters --no-header | awk 'NR==1 {print $1" "$2" "$4}')"
if [ -z "${cluster_line}" ]; then
  echo "[odoo-startup] PostgreSQL cluster not found" >&2
  exit 1
fi

pg_version="$(echo "$cluster_line" | awk '{print $1}')"
pg_name="$(echo "$cluster_line" | awk '{print $2}')"
pg_status="$(echo "$cluster_line" | awk '{print $3}')"

if [ "$pg_status" != "online" ]; then
  pg_ctlcluster "$pg_version" "$pg_name" start
fi

mkdir -p /var/log/odoo /opt/odoo-data
chown -R playground:playground /var/log/odoo /opt/odoo-data

if ! pgrep -u playground -f "/opt/odoo/odoo-bin -c /opt/odoo-lab/odoo.conf" >/dev/null 2>&1; then
  runuser -u playground -- bash -lc \
    "nohup /opt/odoo-venv/bin/python /opt/odoo/odoo-bin -c /opt/odoo-lab/odoo.conf >/var/log/odoo/server.log 2>&1 &"
fi

for _ in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:8069/web/login >/dev/null 2>&1; then
    return 0
  fi
  sleep 1
done

echo "[odoo-startup] Odoo HTTP service did not become ready in time" >&2
return 1

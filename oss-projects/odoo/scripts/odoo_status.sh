#!/bin/bash
set -euo pipefail

echo "Odoo URL: http://127.0.0.1:8069"
echo "Admin: admin@lab.local / adminpass"
echo "Employee: employee@lab.local / employeepass"
echo "Portal: portal@lab.local / portalpass"
echo

if curl -fsS http://127.0.0.1:8069/web/login >/dev/null 2>&1; then
  echo "HTTP: ready"
else
  echo "HTTP: not ready"
fi

echo
echo "PostgreSQL clusters:"
pg_lsclusters || true

echo
echo "Recent Odoo log:"
tail -n 30 /var/log/odoo/server.log 2>/dev/null || true

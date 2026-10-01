#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POC_OUT_DIR="${POC_OUT_DIR:-$SCRIPT_DIR/output}"

mkdir -p "$POC_OUT_DIR"

echo "[*] Output directory: $POC_OUT_DIR"
echo "[*] Waiting for Odoo and exploiting export wizard as employee@lab.local"

/opt/odoo-venv/bin/python "$SCRIPT_DIR/poc.py"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${POC_OUT_DIR:-$SCRIPT_DIR/run-output}"

mkdir -p "$OUT_DIR"
export POC_OUT_DIR="$OUT_DIR"

echo "[*] Writing PoC artifacts to $POC_OUT_DIR"
/opt/odoo-venv/bin/python "$SCRIPT_DIR/poc.py"

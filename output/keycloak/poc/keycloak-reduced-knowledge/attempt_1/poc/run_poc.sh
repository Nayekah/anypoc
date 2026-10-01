#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export EVIDENCE_DIR="${EVIDENCE_DIR:-/home/playground/output/attempt_1/evidence}"
exec python3 ./poc.py

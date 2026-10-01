#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE_ROOT=${EVIDENCE_ROOT:-/home/playground/output/attempt_2/evidence}
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
EVIDENCE_DIR=${EVIDENCE_DIR:-"${EVIDENCE_ROOT}/run-${TIMESTAMP}"}

mkdir -p "${EVIDENCE_DIR}"

exec python3 "${SCRIPT_DIR}/poc.py" --evidence-dir "${EVIDENCE_DIR}"

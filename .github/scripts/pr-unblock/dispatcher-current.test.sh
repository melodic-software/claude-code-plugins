#!/usr/bin/env bash
# Tests for dispatcher-current.sh with stub gh and git on PATH. The stub gh
# serves the Actions run and contents reads; the stub git prints the tip's blob.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/dispatcher-current.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HEAD=1111111111111111111111111111111111111111
BLOB_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BLOB_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
UNBLOCK=.github/workflows/pr-unblock-dispatch.yml
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$2" >>"$STUB/calls"
case $2 in
repos/o/r/actions/runs/*)
  [[ -f $STUB/fail_run ]] && exit 1
  cat "$STUB/run"
  ;;
repos/o/r/contents/*)
  [[ -f $STUB/fail_contents ]] && exit 1
  cat "$STUB/blob"
  ;;
*) exit 1 ;;
esac
STUB
cat >"$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/git"
cat "$STUB/tip"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/git"

# run_case <path> <head> <blob at that head> <blob at the tip> [run id]
run_case() {
  STUB="$(mktemp -d "$TMP/case.XXXXXX")"
  printf '%s\n%s\n' "$1" "$2" >"$STUB/run"
  printf '%s\n' "$3" >"$STUB/blob"
  printf '%s\n' "$4" >"$STUB/tip"
  : >"$STUB/calls"
  : >"$STUB/git"
  : >"$STUB/output"
  [[ -z ${FAIL:-} ]] || : >"$STUB/$FAIL"
  set +e
  env PATH="$TMP/bin:$PATH" STUB="$STUB" GH_TOKEN=t GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$STUB/output" \
    DISPATCHER_RUN_ID="${5-41217038328}" "$SUT" >"$STUB/out" 2>&1
  RC=$?
  set -e
}

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_A"
check "same file: exit 0" 0 "$RC"
check "same file: not stale" '' "$(cat "$STUB/output")"
check "same file: reads the run, then the file at its head" \
  "repos/o/r/actions/runs/41217038328 repos/o/r/contents/$UNBLOCK?ref=$HEAD" "$(tr '\n' ' ' <"$STUB/calls" | sed 's/ $//')"
check "same file: reads the tip's blob of that path" "-C .base rev-parse -q --verify HEAD:$UNBLOCK" "$(cat "$STUB/git")"

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
check "older file: exit 0" 0 "$RC"
check "older file: stale" 'stale=true' "$(cat "$STUB/output")"
check "older file: one warning naming the file" 1 "$(grep -c "^::warning::dispatcher-stale: $UNBLOCK" "$STUB/out")"

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" ''
check "file gone from the tip: stale" 'stale=true' "$(cat "$STUB/output")"

run_case .github/workflows/pr-feedback-dispatch.yml "$HEAD" "$BLOB_A" "$BLOB_B"
check "the run's own dispatcher file is compared: stale" 'stale=true' "$(cat "$STUB/output")"
check "the run's own dispatcher file is the one read" "repos/o/r/contents/.github/workflows/pr-feedback-dispatch.yml?ref=$HEAD" "$(tail -n 1 "$STUB/calls")"

for fault in fail_run fail_contents; do
  FAIL=$fault run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
  check "$fault: exit 0" 0 "$RC"
  check "$fault: left to the broker" '' "$(cat "$STUB/output")"
  check "$fault: says so" 1 "$(grep -c '^::notice::.*the token broker decides$' "$STUB/out")"
done

run_case "$UNBLOCK" "$HEAD" 'not a blob' "$BLOB_B"
check "an unreadable blob is left to the broker" '' "$(cat "$STUB/output")"

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B" '1/../2'
check "a malformed run id reads nothing" '' "$(cat "$STUB/calls")"
check "a malformed run id: exit 0" 0 "$RC"

run_case '../secrets.yml' "$HEAD" "$BLOB_A" "$BLOB_B"
check "a path outside the workflows reads no contents" 'repos/o/r/actions/runs/41217038328' "$(cat "$STUB/calls")"
run_case "$UNBLOCK" 'main' "$BLOB_A" "$BLOB_B"
check "a head that is no commit id reads no contents" 'repos/o/r/actions/runs/41217038328' "$(cat "$STUB/calls")"

exit "$FAILED"

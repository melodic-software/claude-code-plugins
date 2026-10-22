#!/usr/bin/env bash
# Conformance check for a findings-buffer adapter: conformance.sh <adapter-dir>
# Runs the adapter's append.sh and read.sh inside a throwaway git repository.
# Exit: 0 every check passed, 1 a check failed, 2 usage, 3 jq missing.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "usage: conformance.sh <adapter-dir>" >&2
  exit 2
fi
ADAPTER="$(cd "$1" && pwd)"
command -v jq >/dev/null 2>&1 || {
  echo "conformance.sh: prerequisite missing: jq" >&2
  exit 3
}

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CASE_NUM" "$1"
  [[ -n "${2:-}" ]] && printf '  %s\n' "$2"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
git init -q -b main "$REPO" >/dev/null 2>&1 || {
  echo "conformance.sh: git init failed" >&2
  exit 1
}

append() { (cd "$REPO" && bash "$ADAPTER/append.sh" "$@"); }
read_rows() { (cd "$REPO" && bash "$ADAPTER/read.sh" "$@"); }

# capabilities.json
CAPS="$ADAPTER/capabilities.json"
if [[ -f "$CAPS" ]] \
  && jq -e '.schema_version == "1.0" and (.adapter | type == "string" and length > 0)' "$CAPS" >/dev/null 2>&1; then
  pass "capabilities.json declares schema_version 1.0 and an adapter name"
else
  fail "capabilities.json declares schema_version 1.0 and an adapter name"
fi

# 8 concurrent appends, distinct rows
N=8
pids=()
for i in $(seq 1 $N); do
  printf '{"obs_id":"c%d-a","ts":"2026-10-21T10:00:0%dZ","n":%d}\n{"obs_id":"c%d-b","ts":"2026-10-21T10:00:0%dZ","n":%d}\n' \
    "$i" "$i" "$i" "$i" "$i" "$i" >"$WORK/rows-$i.jsonl"
  append <"$WORK/rows-$i.jsonl" >/dev/null 2>"$WORK/append-$i.err" &
  pids+=($!)
done
bad=0
for p in "${pids[@]}"; do wait "$p" || bad=$((bad + 1)); done
if [[ $bad -eq 0 ]]; then
  pass "8 concurrent append.sh calls all exit 0"
else
  fail "8 concurrent append.sh calls all exit 0" "$bad call(s) failed"
fi

OUT="$(read_rows 2>/dev/null)"
RC=$?
miss=""
for i in $(seq 1 $N); do
  for s in a b; do
    cnt="$(printf '%s\n' "$OUT" | grep -c "\"obs_id\":\"c$i-$s\"")"
    [[ "$cnt" == 1 ]] || miss="$miss c$i-$s(x$cnt)"
  done
done
total="$(printf '%s\n' "$OUT" | grep -c '^{')"
if [[ $RC -eq 0 && -z "$miss" && "$total" -eq $((N * 2)) ]]; then
  pass "read.sh returns every appended row exactly once"
else
  fail "read.sh returns every appended row exactly once" "exit $RC, rows $total, off:$miss"
fi

# --since compares the top-level ts, not a nested one
printf '{"obs_id":"nested","ctx":{"ts":"2026-01-01T00:00:00Z"},"ts":"2026-10-21T10:00:09Z"}\n' \
  | append >/dev/null 2>&1

OUT="$(read_rows --since 2026-10-21T10:00:05Z 2>/dev/null)"
RC=$?
miss=""
grep -q '"obs_id":"nested"' <<<"$OUT" || miss="$miss nested"
for i in 5 6 7 8; do
  for s in a b; do
    grep -q "\"obs_id\":\"c$i-$s\"" <<<"$OUT" || miss="$miss c$i-$s"
  done
done
if [[ $RC -eq 0 && -z "$miss" ]]; then
  pass "read.sh --since returns every row with ts >= since"
else
  fail "read.sh --since returns every row with ts >= since" "exit $RC, missing:$miss"
fi

# a malformed row is a usage error and stores nothing from that call
printf '{oops}\n{"obs_id":"bad-call","ts":"2026-10-21T10:00:00Z"}\n' | append >/dev/null 2>&1
RC=$?
if [[ $RC -eq 2 ]] && ! grep -q '"obs_id":"bad-call"' <<<"$(read_rows 2>/dev/null)"; then
  pass "append.sh rejects a malformed row with exit 2 and stores nothing"
else
  fail "append.sh rejects a malformed row with exit 2 and stores nothing" "exit $RC"
fi

# malformed arguments
expect_usage() { # <exit code> <name>
  if [[ "$1" -eq 2 ]]; then pass "$2"; else fail "$2" "got exit $1"; fi
}
read_rows --bogus >/dev/null 2>&1
expect_usage $? "read.sh with an unknown argument exits 2"
read_rows --since not-a-time >/dev/null 2>&1
expect_usage $? "read.sh --since with a malformed value exits 2"
append --bogus </dev/null >/dev/null 2>&1
expect_usage $? "append.sh with an argument exits 2"

printf '1..%d\n' "$CASE_NUM"
[[ $FAILED -eq 0 ]]

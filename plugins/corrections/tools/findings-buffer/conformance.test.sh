#!/usr/bin/env bash
# Tests for conformance.sh: it passes the local-file adapter, fails adapters that
# break the contract, and rejects a bad invocation with exit 2.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/conformance.sh"
LOCAL="$SCRIPT_DIR/adapters/local-file"

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
  if [[ -n "${2:-}" ]]; then printf '  %s\n' "$2"; fi
}
# expect_exit <want> <got> <name>
expect_exit() {
  if [[ "$2" -eq "$1" ]]; then
    pass "$3"
  else
    fail "$3" "wanted exit $1, got $2"
  fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "1..0 # SKIP git not available"
  exit 0
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# local-file passes
OUT="$(bash "$CONF" "$LOCAL" 2>&1)"
RC=$?
if [[ $RC -eq 0 ]]; then
  pass "conformance.sh passes the local-file adapter"
else
  fail "conformance.sh passes the local-file adapter" "exit $RC: $OUT"
fi

bash "$CONF" >/dev/null 2>&1
expect_exit 2 $? "no adapter-dir exits 2"

bash "$CONF" "$TEST_TMPDIR/nope" >/dev/null 2>&1
expect_exit 2 $? "a missing adapter-dir exits 2"

# make_broken <name>: a copy of local-file to sabotage; prints its directory.
make_broken() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d"
  cp "$LOCAL/append.sh" "$LOCAL/read.sh" "$LOCAL/capabilities.json" "$d/"
  printf '%s\n' "$d"
}

# an adapter that stores only the first line of each call loses rows
D="$(make_broken drops)"
cat >"$D/append.sh" <<'EOF'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)" || exit 3
mkdir -p "$ROOT/.work/buffer"
head -n 1 >>"$ROOT/.work/buffer/findings.jsonl"
EOF
bash "$CONF" "$D" >/dev/null 2>&1
expect_exit 1 $? "an adapter that loses a row fails"

# an unsupported schema_version
D="$(make_broken badcaps)"
printf '{"schema_version":"2.0","adapter":"x"}\n' >"$D/capabilities.json"
bash "$CONF" "$D" >/dev/null 2>&1
expect_exit 1 $? "an unsupported schema_version fails"

# a reader that ignores its arguments
D="$(make_broken lax)"
cat >"$D/read.sh" <<'EOF'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)" || exit 3
cat "$ROOT/.work/buffer/findings.jsonl" 2>/dev/null
exit 0
EOF
bash "$CONF" "$D" >/dev/null 2>&1
expect_exit 1 $? "an adapter that accepts a bad argument fails"

# local-file stores under .work/buffer/findings.jsonl
REPO="$TEST_TMPDIR/repo"
git init -q -b main "$REPO" >/dev/null 2>&1
printf '{"obs_id":"x","ts":"2026-10-21T00:00:00Z"}\n' | (cd "$REPO" && bash "$LOCAL/append.sh")
if [[ -s "$REPO/.work/buffer/findings.jsonl" ]]; then
  pass "local-file creates .work/buffer/findings.jsonl on first append"
else
  fail "local-file creates .work/buffer/findings.jsonl on first append"
fi

# a malformed row stores nothing and exits 2
printf '{"obs_id":"y","ts":"2026-10-21T00:00:01Z"}\nnot json\n' | (cd "$REPO" && bash "$LOCAL/append.sh" >/dev/null 2>&1)
expect_exit 2 $? "append.sh with a malformed row exits 2"
if [[ "$(wc -l <"$REPO/.work/buffer/findings.jsonl")" -eq 1 ]]; then
  pass "a malformed row stores nothing from that call"
else
  fail "a malformed row stores nothing from that call"
fi

# outside a repository
NOREPO="$TEST_TMPDIR/norepo"
mkdir -p "$NOREPO"
(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$LOCAL/read.sh" >/dev/null 2>&1)
expect_exit 3 $? "read.sh outside a repository exits 3"

printf '1..%d\n' "$CASE_NUM"
[[ $FAILED -eq 0 ]]

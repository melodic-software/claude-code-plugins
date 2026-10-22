#!/usr/bin/env bash
# Tests for buffer.sh: adapter binding, fallback, obs_id, redaction, caps and dedupe.
# test-scope: plugins/session-flow/skills/audit-sessions/vendor/gitleaks/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUFFER="$SCRIPT_DIR/buffer.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

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
# check <name> <command...>: passes when the command exits 0.
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name" "${DETAIL:-}"; fi
  DETAIL=""
}

for tool in git node python3 jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "1..0 # SKIP $tool not available"
    exit 0
  fi
done

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
N=0

# new_repo: sets R to a new empty git repository.
new_repo() {
  N=$((N + 1))
  R="$TEST_TMPDIR/repo$N"
  mkdir -p "$R"
  git -C "$R" init -q
}
# bind <repo> <adapter-token>: writes the team binding.
bind() {
  mkdir -p "$1/docs/conventions"
  printf 'adapter: %s\n' "$2" >"$1/docs/conventions/findings-buffer.yaml"
}
# fake_adapter <repo> <dir> <append-exit>: an adapter that copies each append to
# <dir>/captured.jsonl and exits <append-exit>; read.sh prints that file.
fake_adapter() {
  local d="$1/$2"
  mkdir -p "$d"
  printf '{"schema_version":"1.0","adapter":"fake"}\n' >"$d/capabilities.json"
  cat >"$d/append.sh" <<EOF
#!/usr/bin/env bash
cat >>"\$(dirname "\$0")/captured.jsonl"
exit $3
EOF
  cat >"$d/read.sh" <<'EOF'
#!/usr/bin/env bash
f="$(dirname "$0")/captured.jsonl"
[[ -f "$f" ]] && cat "$f"
exit 0
EOF
  chmod +x "$d/append.sh" "$d/read.sh"
}
# run <repo> <args...>: buffer.sh from inside <repo>; stdout to $OUT, stderr to $ERR.
run() {
  local repo="$1"
  shift
  (cd "$repo" && bash "$BUFFER" "$@") >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err"
  RC=$?
  OUT="$(cat "$TEST_TMPDIR/out")"
  ERR="$(cat "$TEST_TMPDIR/err")"
}
# used_local <rc> <repo> <stderr>: the append succeeded into the local file and said so.
used_local() { [[ $1 -eq 0 && -s "$2/.work/buffer/findings.jsonl" ]] && grep -q "local-file" <<<"$3"; }
local_rows() { cat "$1/.work/buffer/findings.jsonl" 2>/dev/null; }

ROW='{"kind":"lint","session":"s1","msg":"unused variable"}'

# 1. No binding uses local-file and says so.
new_repo
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "no binding: append exits 0" test "$RC" -eq 0
DETAIL="local rows: $(local_rows "$R")"
GOT="$(jq -r 'select(.msg == "unused variable") | (.obs_id | test("^[0-9a-f]{16}$")) and (.ts | type == "string")' "$R/.work/buffer/findings.jsonl" 2>/dev/null)"
check "no binding: the row lands in the local file with obs_id and ts" test "$GOT" == true
DETAIL="stderr: $ERR"
check "no binding: stderr names local-file" grep -q "local-file" <<<"$ERR"

# 2. A bound adapter that fails falls back to the local file.
new_repo
fake_adapter "$R" adapters/broken 1
bind "$R" adapters/broken
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "failing adapter: append still exits 0" test "$RC" -eq 0
DETAIL="local rows: $(local_rows "$R")"
check "failing adapter: the row is in the local file" grep -q '"unused variable"' "$R/.work/buffer/findings.jsonl"
run "$R" read
DETAIL="exit $RC; out: $OUT"
check "failing adapter: read merges the adapter and fallback rows, once per obs_id" \
  test "$RC" -eq 0 -a "$(grep -c '"unused variable"' <<<"$OUT")" -eq 1

# 3. A retried row keeps its obs_id and reads back once.
new_repo
fake_adapter "$R" adapters/ok 0
bind "$R" adapters/ok
run "$R" append < <(printf '%s\n' "$ROW")
run "$R" append < <(printf '%s\n' "$ROW")
IDS="$(jq -r .obs_id "$R/adapters/ok/captured.jsonl" | sort -u | wc -l)"
DETAIL="captured: $(cat "$R/adapters/ok/captured.jsonl")"
check "retry: both appends reach the adapter with one obs_id" \
  test "$(wc -l <"$R/adapters/ok/captured.jsonl")" -eq 2 -a "$IDS" -eq 1
run "$R" read
DETAIL="exit $RC; out: $OUT"
check "retry: read returns the row once" test "$RC" -eq 0 -a "$(grep -c . <<<"$OUT")" -eq 1
OTHER='{"kind":"lint","session":"s2","msg":"unused variable"}'
run "$R" append < <(printf '%s\n' "$OTHER")
DETAIL="captured: $(cat "$R/adapters/ok/captured.jsonl")"
check "retry: the same finding in another session gets its own obs_id" \
  test "$(jq -r .obs_id "$R/adapters/ok/captured.jsonl" | sort -u | wc -l)" -eq 2
run "$R" append < <(printf '{"obs_id":"0123456789abcdef","msg":"caller id"}\n')
check "a caller obs_id of 16 hex characters is kept" grep -q '"obs_id":"0123456789abcdef"' "$R/adapters/ok/captured.jsonl"

# 4. A planted fake token is redacted before it reaches the adapter.
new_repo
fake_adapter "$R" adapters/ok 0
bind "$R" adapters/ok
TOKEN="$(printf '%s%s%s' AKIA IOSFODNN7 EXAMPLE)"
run "$R" append < <(printf '{"msg":"export AWS_ACCESS_KEY_ID=%s then deploy","nested":{"list":["%s"]}}\n' "$TOKEN" "$TOKEN")
DETAIL="exit $RC; captured: $(cat "$R/adapters/ok/captured.jsonl" 2>/dev/null)"
check "redaction: append exits 0" test "$RC" -eq 0
check "redaction: the token never reaches the adapter" test "$(grep -c "$TOKEN" "$R/adapters/ok/captured.jsonl")" -eq 0
check "redaction: a redaction marker takes its place" grep -q '<redacted:' "$R/adapters/ok/captured.jsonl"

# 5. An oversize row is capped.
new_repo
fake_adapter "$R" adapters/ok 0
bind "$R" adapters/ok
BIG="$(head -c 6000 /dev/zero | tr '\0' 'x')"
run "$R" append < <(printf '{"session":"s1","msg":"%s","small":"keep"}\n' "$BIG")
run "$R" append < <(printf '{"session":"s1","msg":"%s","small":"keep"}\n' "$BIG")
LINE="$(head -n 1 "$R/adapters/ok/captured.jsonl")"
DETAIL="exit $RC; bytes: $(printf '%s' "$LINE" | wc -c)"
check "cap: the stored row is at most 2048 bytes" test "$(printf '%s' "$LINE" | wc -c)" -le 2048
DETAIL="row: ${LINE:0:200}"
GOT="$(jq -r '(.truncated == true) and (.small == "keep") and (.session == "s1")' <<<"$LINE")"
check "cap: the row says it was truncated and keeps its short values" test "$GOT" == true
check "cap: a retried oversize row keeps its obs_id" \
  test "$(jq -r .obs_id "$R/adapters/ok/captured.jsonl" | sort -u | wc -l)" -eq 1
ARR="$(printf '"%s",' $(seq 1 600) | sed 's/,$//')"
run "$R" append < <(printf '{"session":"s1","list":[%s]}\n' "$ARR")
LINE="$(tail -n 1 "$R/adapters/ok/captured.jsonl")"
DETAIL="exit $RC; row: ${LINE:0:200}"
SIZE="$(printf '%s' "$LINE" | wc -c)"
GOT="$(jq -r '(.truncated == true) and (.list | type == "string")' <<<"$LINE")"
check "cap: a large array is replaced by a size note, never rejected" \
  test "$RC" -eq 0 -a "$SIZE" -le 2048 -a "$GOT" == true

# 6. A redaction failure writes nothing anywhere.
new_repo
fake_adapter "$R" adapters/ok 0
bind "$R" adapters/ok
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\nexit 1\n' >"$SHIM/python3"
chmod +x "$SHIM/python3"
PATH="$SHIM:$PATH" run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "redaction failure: append exits non-zero" test "$RC" -ne 0
check "redaction failure: nothing reaches the adapter or the local file" \
  test ! -e "$R/adapters/ok/captured.jsonl" -a ! -e "$R/.work/buffer/findings.jsonl"

# 7. An adapter path outside the repository is an invalid binding.
new_repo
OUTSIDE="$R"
fake_adapter "$OUTSIDE" evil 0
new_repo
bind "$R" "../$(basename "$OUTSIDE")/evil"
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a dotdot adapter path: append uses local-file and says so" \
  used_local "$RC" "$R" "$ERR"
check "a dotdot adapter path: the outside adapter never runs" test ! -e "$OUTSIDE/evil/captured.jsonl"
new_repo
ln -s "$OUTSIDE/evil" "$R/linked"
bind "$R" linked
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a symlink to an outside adapter: append uses local-file and says so" \
  used_local "$RC" "$R" "$ERR"
check "a symlink to an outside adapter: it never runs" test ! -e "$OUTSIDE/evil/captured.jsonl"

# Usage.
new_repo
run "$R" bogus
check "an unknown verb exits 2" test "$RC" -eq 2
run "$R" read --since yesterday
check "a bad --since exits 2" test "$RC" -eq 2

# The vendored rules match the canonical copy byte for byte.
CANON="$REPO_ROOT/plugins/session-flow/skills/audit-sessions/vendor/gitleaks"
for f in gitleaks-rules.json LICENSE-gitleaks; do
  check "vendored $f matches the session-flow copy" cmp -s "$CANON/$f" "$SCRIPT_DIR/vendor/gitleaks/$f"
done

printf '1..%d\n' "$CASE_NUM"
if [[ $FAILED -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi

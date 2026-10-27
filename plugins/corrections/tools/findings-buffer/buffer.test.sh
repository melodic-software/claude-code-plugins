#!/usr/bin/env bash
# Tests for buffer.sh: adapter binding, fallback, obs_id, redaction, caps and dedupe.
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
# The core runs only adapters shipped under the plugin's own adapters/, so the cases run a copy of
# the plugin with their fake adapters installed there. The copy sits in a marketplace install
# layout, so it reads the user-scope binding from $CONFIG/settings.json.
CONFIG="$TEST_TMPDIR/config"
PLUGIN_COPY="$CONFIG/plugins/cache/mkt/corrections/1.0.0"
mkdir -p "$(dirname "$PLUGIN_COPY")"
cp -R "$REPO_ROOT/plugins/corrections" "$PLUGIN_COPY"
BUFFER="$PLUGIN_COPY/tools/findings-buffer/buffer.sh"
ADAPTERS="$PLUGIN_COPY/tools/findings-buffer/adapters"

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
# fake_adapter <dir> <append-exit>: an adapter that copies each append to <dir>/captured.jsonl
# and exits <append-exit>; read.sh prints that file.
fake_adapter() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d"
  printf '{"schema_version":"1.0","adapter":"fake"}\n' >"$d/capabilities.json"
  cat >"$d/append.sh" <<EOF
#!/usr/bin/env bash
cat >>"\$(dirname "\$0")/captured.jsonl"
exit $2
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
fake_adapter "$ADAPTERS/broken" 1
bind "$R" broken
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
fake_adapter "$ADAPTERS/ok" 0
bind "$R" ok
run "$R" append < <(printf '%s\n' "$ROW")
run "$R" append < <(printf '%s\n' "$ROW")
IDS="$(jq -r .obs_id "$ADAPTERS/ok/captured.jsonl" | sort -u | wc -l)"
DETAIL="captured: $(cat "$ADAPTERS/ok/captured.jsonl")"
check "retry: both appends reach the adapter with one obs_id" \
  test "$(wc -l <"$ADAPTERS/ok/captured.jsonl")" -eq 2 -a "$IDS" -eq 1
run "$R" read
DETAIL="exit $RC; out: $OUT"
check "retry: read returns the row once" test "$RC" -eq 0 -a "$(grep -c . <<<"$OUT")" -eq 1
OTHER='{"kind":"lint","session":"s2","msg":"unused variable"}'
run "$R" append < <(printf '%s\n' "$OTHER")
DETAIL="captured: $(cat "$ADAPTERS/ok/captured.jsonl")"
check "retry: the same finding in another session gets its own obs_id" \
  test "$(jq -r .obs_id "$ADAPTERS/ok/captured.jsonl" | sort -u | wc -l)" -eq 2
run "$R" append < <(printf '{"obs_id":"0123456789abcdef","msg":"caller id"}\n')
check "a caller obs_id of 16 hex characters is kept" grep -q '"obs_id":"0123456789abcdef"' "$ADAPTERS/ok/captured.jsonl"

# 4. A planted fake token is redacted before it reaches the adapter.
new_repo
fake_adapter "$ADAPTERS/ok" 0
bind "$R" ok
TOKEN="$(printf '%s%s%s' AKIA IOSFODNN7 EXAMPLE)"
run "$R" append < <(printf '{"msg":"export AWS_ACCESS_KEY_ID=%s then deploy","nested":{"list":["%s"]}}\n' "$TOKEN" "$TOKEN")
DETAIL="exit $RC; captured: $(cat "$ADAPTERS/ok/captured.jsonl" 2>/dev/null)"
check "redaction: append exits 0" test "$RC" -eq 0
check "redaction: the token never reaches the adapter" test "$(grep -c "$TOKEN" "$ADAPTERS/ok/captured.jsonl")" -eq 0
check "redaction: a redaction marker takes its place" grep -q '<redacted:' "$ADAPTERS/ok/captured.jsonl"
run "$R" append < <(printf '{"msg":"keyed","%s":"v"}\n' "$TOKEN")
DETAIL="exit $RC; captured: $(tail -n 1 "$ADAPTERS/ok/captured.jsonl" 2>/dev/null)"
check "redaction: a token used as an object key never reaches the adapter" \
  test "$RC" -eq 0 -a "$(grep -c "$TOKEN" "$ADAPTERS/ok/captured.jsonl")" -eq 0

# 5. An oversize row is capped.
new_repo
fake_adapter "$ADAPTERS/ok" 0
bind "$R" ok
BIG="$(head -c 6000 /dev/zero | tr '\0' 'x')"
run "$R" append < <(printf '{"session":"s1","msg":"%s","small":"keep"}\n' "$BIG")
run "$R" append < <(printf '{"session":"s1","msg":"%s","small":"keep"}\n' "$BIG")
LINE="$(head -n 1 "$ADAPTERS/ok/captured.jsonl")"
DETAIL="exit $RC; bytes: $(printf '%s' "$LINE" | wc -c)"
check "cap: the stored row is at most 2048 bytes" test "$(printf '%s' "$LINE" | wc -c)" -le 2048
DETAIL="row: ${LINE:0:200}"
GOT="$(jq -r '(.truncated == true) and (.small == "keep") and (.session == "s1")' <<<"$LINE")"
check "cap: the row says it was truncated and keeps its short values" test "$GOT" == true
check "cap: a retried oversize row keeps its obs_id" \
  test "$(jq -r .obs_id "$ADAPTERS/ok/captured.jsonl" | sort -u | wc -l)" -eq 1
ARR="$(printf '"%s",' $(seq 1 600) | sed 's/,$//')"
run "$R" append < <(printf '{"session":"s1","list":[%s]}\n' "$ARR")
LINE="$(tail -n 1 "$ADAPTERS/ok/captured.jsonl")"
DETAIL="exit $RC; row: ${LINE:0:200}"
SIZE="$(printf '%s' "$LINE" | wc -c)"
GOT="$(jq -r '(.truncated == true) and (.list | type == "string")' <<<"$LINE")"
check "cap: a large array is replaced by a size note, never rejected" \
  test "$RC" -eq 0 -a "$SIZE" -le 2048 -a "$GOT" == true
HALF="$(head -c 1500 /dev/zero | tr '\0' 'y')"
run "$R" append < <(printf '{"session":"s1","first":"%s","second":"%s"}\n' "$HALF" "$HALF")
run "$R" append < <(printf '{"second":"%s","first":"%s","session":"s1"}\n' "$HALF" "$HALF")
DETAIL="obs_ids: $(tail -n 2 "$ADAPTERS/ok/captured.jsonl" | jq -r .obs_id | tr '\n' ' ')"
check "cap: key order does not change what is trimmed or the obs_id" \
  test "$(tail -n 2 "$ADAPTERS/ok/captured.jsonl" | jq -r .obs_id | sort -u | wc -l)" -eq 1

# 6. A redaction failure writes nothing anywhere.
new_repo
fake_adapter "$ADAPTERS/ok" 0
bind "$R" ok
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\nexit 1\n' >"$SHIM/python3"
chmod +x "$SHIM/python3"
PATH="$SHIM:$PATH" run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "redaction failure: append exits non-zero" test "$RC" -ne 0
check "redaction failure: nothing reaches the adapter or the local file" \
  test ! -e "$ADAPTERS/ok/captured.jsonl" -a ! -e "$R/.work/buffer/findings.jsonl"

# 7. A committed binding never runs repository code: only a plugin adapter name is accepted.
new_repo
fake_adapter "$R/evil" 0
fake_adapter "$R/tools/evil" 0
for token in evil tools/evil ./evil; do
  bind "$R" "$token"
  run "$R" append < <(printf '%s\n' "$ROW")
  DETAIL="exit $RC; stderr: $ERR"
  check "a committed binding to repository code ($token): append uses local-file and says so" \
    used_local "$RC" "$R" "$ERR"
done
check "a committed binding to repository code: it never runs" \
  test ! -e "$R/evil/captured.jsonl" -a ! -e "$R/tools/evil/captured.jsonl"
bind "$R" ".."
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a dotdot adapter name: append uses local-file and says so" used_local "$RC" "$R" "$ERR"
ln -s "$R/evil" "$ADAPTERS/linked"
bind "$R" linked
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a plugin adapter name that links outside adapters/: append uses local-file and says so" \
  used_local "$RC" "$R" "$ERR"
check "a plugin adapter name that links outside adapters/: it never runs" test ! -e "$R/evil/captured.jsonl"

# 8. A user-scope binding runs the repository's own adapter, in that repository only.
# user_bind <repository> <path>: the user-scope binding, in the install's user settings.
user_bind() {
  jq -n --arg r "$1" --arg p "$2" \
    '{pluginConfigs: {"corrections@mkt": {options: {findings_buffer_adapter_repository: $r, findings_buffer_adapter_path: $p}}}}' \
    >"$CONFIG/settings.json"
}
# refused_user <rc> <repo> <stderr>: the user-scope binding was refused and the append used local-file.
refused_user() { used_local "$1" "$2" "$3" && grep -q "user-scope adapter binding is refused" <<<"$3"; }

new_repo
A="$R"
fake_adapter "$A/tools/mine" 0
user_bind "$A/.git" tools/mine
run "$A" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "user-scope binding: append exits 0" test "$RC" -eq 0
check "user-scope binding: the repository's adapter runs" grep -q '"unused variable"' "$A/tools/mine/captured.jsonl"
check "user-scope binding: nothing lands in the local file" test ! -e "$A/.work/buffer/findings.jsonl"

new_repo
B="$R"
fake_adapter "$B/tools/mine" 0
run "$B" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a binding made for repository A, in B with the same layout: append uses local-file" used_local "$RC" "$B" "$ERR"
check "a binding made for repository A, in B with the same layout: B's adapter never runs" \
  test ! -e "$B/tools/mine/captured.jsonl"

rm -f "$A/tools/mine/captured.jsonl"
git -C "$A" add -A
git -C "$A" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm fixture
W="$TEST_TMPDIR/worktree-of-a"
git -C "$A" worktree add -q "$W"
run "$W" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a binding made for repository A applies in a worktree of A" \
  test "$RC" -eq 0 -a -s "$W/tools/mine/captured.jsonl"

# A plain directory whose .git file names A's git directory is not a checkout A registers.
H="$TEST_TMPDIR/claims-a"
mkdir -p "$H"
printf 'gitdir: %s\n' "$A/.git" >"$H/.git"
fake_adapter "$H/tools/mine" 0
run "$H" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a directory whose .git file names A's git directory: refused, append uses local-file and says so" \
  refused_user "$RC" "$H" "$ERR"
check "a directory whose .git file names A's git directory: its adapter never runs" test ! -e "$H/tools/mine/captured.jsonl"

# A repository-written value for the user-scope keys is never read: not from the team file, a
# project settings file or the CLAUDE_PLUGIN_OPTION_* environment.
rm -f "$CONFIG/settings.json"
new_repo
fake_adapter "$R/tools/mine" 0
mkdir -p "$R/docs/conventions" "$R/.claude"
printf 'findings_buffer:\n  adapter_repository: %s\n  adapter_path: tools/mine\n' "$R/.git" \
  >"$R/docs/conventions/findings-buffer.yaml"
jq -n --arg r "$R/.git" \
  '{pluginConfigs: {"corrections@mkt": {options: {findings_buffer_adapter_repository: $r, findings_buffer_adapter_path: "tools/mine"}}}}' \
  >"$R/.claude/settings.json"
CLAUDE_PLUGIN_OPTION_FINDINGS_BUFFER_ADAPTER_REPOSITORY="$R/.git" CLAUDE_PLUGIN_OPTION_FINDINGS_BUFFER_ADAPTER_PATH=tools/mine \
  run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "repository-written user-scope keys: append uses local-file" used_local "$RC" "$R" "$ERR"
check "repository-written user-scope keys: the repository's adapter never runs" test ! -e "$R/tools/mine/captured.jsonl"

# The adapter must resolve inside the checkout and outside any repository nested in it.
new_repo
fake_adapter "$TEST_TMPDIR/outside" 0
ln -s "$TEST_TMPDIR/outside" "$R/out"
mkdir -p "$R/vendor/nested"
git -C "$R/vendor/nested" init -q
fake_adapter "$R/vendor/nested/adapter" 0
ln -s "$R/vendor/nested/adapter" "$R/into"
fake_adapter "$R/tools/abs" 0
# A tracked adapter directory whose append.sh links into a repository nested inside it.
fake_adapter "$R/tools/split" 0
mkdir -p "$R/tools/split/sub"
git -C "$R/tools/split/sub" init -q
mv "$R/tools/split/append.sh" "$R/tools/split/sub/append.sh"
ln -s sub/append.sh "$R/tools/split/append.sh"
for path in out into vendor/nested/adapter tools/split "$R/tools/abs"; do
  user_bind "$R/.git" "$path"
  run "$R" append < <(printf '%s\n' "$ROW")
  DETAIL="exit $RC; stderr: $ERR"
  check "a user-scope binding to ${path#"$R/"}: refused, append uses local-file and says so" refused_user "$RC" "$R" "$ERR"
done
check "a refused user-scope binding never runs" \
  test ! -e "$TEST_TMPDIR/outside/captured.jsonl" -a ! -e "$R/vendor/nested/adapter/captured.jsonl" \
    -a ! -e "$R/tools/split/captured.jsonl" -a ! -e "$R/tools/abs/captured.jsonl"
jq -n '{pluginConfigs: {"corrections@mkt": {options: {findings_buffer_adapter_path: "tools/abs"}}}}' >"$CONFIG/settings.json"
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $ERR"
check "a user-scope binding with one option set: refused, append uses local-file and says so" refused_user "$RC" "$R" "$ERR"
rm -f "$CONFIG/settings.json"

# A binding file of unknown keys prints the first five errors, then a count of the rest.
new_repo
mkdir -p "$R/docs/conventions"
{
  for i in $(seq 1 1200); do printf 'unknown_%d: x\n' "$i"; done
  printf 'adapter: local-file\n'
} >"$R/docs/conventions/findings-buffer.yaml"
run "$R" append < <(printf '%s\n' "$ROW")
DETAIL="exit $RC; stderr: $(head -c 2000 <<<"$ERR")"
check "1200 unknown keys: append exits 0" test "$RC" -eq 0
check "1200 unknown keys: six stderr lines for the layer" test "$(grep -c 'team (' <<<"$ERR")" -eq 6
check "1200 unknown keys: the last line counts the rest" grep -q 'team (.*findings-buffer.yaml): and 1195 more$' <<<"$ERR"

# Usage.
new_repo
run "$R" bogus
check "an unknown verb exits 2" test "$RC" -eq 2
run "$R" read --since yesterday
check "a bad --since exits 2" test "$RC" -eq 2

# --since reaches both reads: an old row in the bound adapter and one in the local file are left out.
new_repo
fake_adapter "$ADAPTERS/broken" 1
cat >"$ADAPTERS/broken/read.sh" <<'EOF'
#!/usr/bin/env bash
f="$(dirname "$0")/captured.jsonl"
[[ -f "$f" ]] || exit 0
if [[ "${1:-}" == --since ]]; then jq -c --arg s "$2" 'select(.ts >= $s)' "$f"; else cat "$f"; fi
EOF
bind "$R" broken
run "$R" append < <(printf '%s\n' "$ROW")
old_row() { printf '{"ts":"2020-01-01T00:00:00Z","session":"s1","msg":"%s","obs_id":"%s"}\n' "$1" "$2"; }
old_row "old adapter row" aaaaaaaaaaaaaaaa >>"$ADAPTERS/broken/captured.jsonl"
old_row "old local row" bbbbbbbbbbbbbbbb >>"$R/.work/buffer/findings.jsonl"
run "$R" read --since 2025-01-01T00:00:00Z
DETAIL="exit $RC; out: $OUT"
check "read --since: both reads leave out rows older than since and keep the new one" \
  test "$RC" -eq 0 -a "$(grep -c 'old .* row' <<<"$OUT")" -eq 0 -a "$(grep -c '"unused variable"' <<<"$OUT")" -eq 1

printf '1..%d\n' "$CASE_NUM"
if [[ $FAILED -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi

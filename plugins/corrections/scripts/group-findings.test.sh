#!/usr/bin/env bash
# Tests for group-findings.mjs: grouping rows from a bound adapter and the local file, the named
# keys, occurrence counts, the exact --since cut, escaping, an empty buffer, usage and a failed read.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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

for tool in git node jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "1..0 # SKIP $tool not available"
    exit 0
  fi
done

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
N=0
# buffer.sh runs only adapters shipped under the plugin's own adapters/, so the cases run a copy of
# the plugin, in a marketplace install layout, with a fake adapter installed there.
CONFIG="$TEST_TMPDIR/config"
PLUGIN_COPY="$CONFIG/plugins/cache/mkt/corrections/1.0.0"
mkdir -p "$(dirname "$PLUGIN_COPY")"
cp -R "$REPO_ROOT/plugins/corrections" "$PLUGIN_COPY"
GROUP="$PLUGIN_COPY/scripts/group-findings.mjs"
ADAPTERS="$PLUGIN_COPY/tools/findings-buffer/adapters"

# new_repo: sets R to a new empty git repository.
new_repo() {
  N=$((N + 1))
  R="$TEST_TMPDIR/repo$N"
  mkdir -p "$R"
  git -C "$R" init -q
}
# fake_adapter <name>: a plugin adapter whose read.sh prints its rows.jsonl.
fake_adapter() {
  local d="$ADAPTERS/$1"
  rm -rf "$d"
  mkdir -p "$d"
  printf '{"schema_version":"1.0","adapter":"fake"}\n' >"$d/capabilities.json"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$d/append.sh"
  cat >"$d/read.sh" <<'EOF'
#!/usr/bin/env bash
f="$(dirname "$0")/rows.jsonl"
[[ -f "$f" ]] && cat "$f"
exit 0
EOF
  chmod +x "$d/append.sh" "$d/read.sh"
}
# local_row <repo> <json>: appends a stored row to the repository's local-file buffer.
local_row() {
  mkdir -p "$1/.work/buffer"
  printf '%s\n' "$2" >>"$1/.work/buffer/findings.jsonl"
}
# run <dir> <args...>: the reader from inside <dir>; stdout to $OUT, stderr to $ERR.
run() {
  local dir="$1"
  shift
  (cd "$dir" && node "$GROUP" "$@") >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err"
  RC=$?
  OUT="$(cat "$TEST_TMPDIR/out")"
  ERR="$(cat "$TEST_TMPDIR/err")"
}
# line_of <text>: the 1-based line number of the first output line equal to <text>, or 0.
line_of() { awk -v want="$1" '$0 == want { print NR; found = 1; exit } END { if (!found) print 0 }' <<<"$OUT"; }

# 1. Rows from two sources, a bound adapter and the local file, grouped by producer.
new_repo
fake_adapter other
mkdir -p "$R/docs/conventions"
printf 'adapter: other\n' >"$R/docs/conventions/findings-buffer.yaml"
cat >"$ADAPTERS/other/rows.jsonl" <<'EOF'
{"obs_id":"aaaaaaaaaaaaaaa1","ts":"2026-10-21T09:00:00Z","producer":"scanner/lint","kind":"unused","source_id":"#20"}
{"obs_id":"aaaaaaaaaaaaaaa2","ts":"2026-10-21T10:00:00Z","producer":"scanner/lint","kind":"shadow","source_id":"#21"}
EOF
local_row "$R" '{"obs_id":"bbbbbbbbbbbbbbb1","ts":"2026-10-22T09:00:00Z","producer":"corrections/codify-note","signal":"ran the tests before the build","source_id":"#12"}'
local_row "$R" '{"obs_id":"bbbbbbbbbbbbbbb2","ts":"2026-10-22T08:00:00Z","producer":"corrections/codify-note","signal":"skipped the changelog","source_id":"#12"}'
local_row "$R" '{"obs_id":"bbbbbbbbbbbbbbb3","ts":"2026-10-22T10:00:00Z","producer":"corrections/codify-note","signal":"ran the tests before the build","source_id":"#13"}'
local_row "$R" '{"obs_id":"bbbbbbbbbbbbbbb4","ts":"2026-10-22T11:00:00Z","kind":"unused"}'
# More rows than any other group, but one occurrence: it ranks below the two-occurrence groups.
for i in 1 2 3 4; do
  local_row "$R" "{\"obs_id\":\"eeeeeeeeeeeeeee$i\",\"ts\":\"2026-10-23T0$i:00:00Z\",\"producer\":\"scanner/dup\",\"source_id\":\"#30\"}"
done
# A row both sources hold is grouped once.
local_row "$R" '{"obs_id":"aaaaaaaaaaaaaaa1","ts":"2026-10-21T09:00:00Z","producer":"scanner/lint","kind":"unused","source_id":"#20"}'
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "two sources: exits 0" test "$RC" -eq 0
DETAIL="out: $OUT"
check "two sources: the first line names the grouping key" test "$(head -n 1 <<<"$OUT")" == "grouped by: producer"
DETAIL="out: $OUT"
check "two sources: the totals count each obs_id once" grep -qx '4 groups, 10 rows' <<<"$OUT"
NOTE="$(line_of 'producer="corrections/codify-note": 3 rows, 2 occurrences')"
LINT="$(line_of 'producer="scanner/lint": 2 rows, 2 occurrences')"
DUP="$(line_of 'producer="scanner/dup": 4 rows, 1 occurrence')"
NONE="$(line_of 'producer=(none): 1 row, 1 occurrence')"
DETAIL="out: $OUT"
check "two sources: each group shows its rows and occurrences" \
  test "$NOTE" -gt 0 -a "$LINT" -gt 0 -a "$DUP" -gt 0 -a "$NONE" -gt 0
DETAIL="out: $OUT"
check "two sources: groups come most occurrences first, then most rows" \
  test "$NOTE" -lt "$LINT" -a "$LINT" -lt "$DUP" -a "$DUP" -lt "$NONE"
FIRST="$(sed -n "$((NOTE + 1))p" <<<"$OUT")"
DETAIL="first member: $FIRST"
check "two sources: members come oldest first with obs_id, ts and source_id" \
  test "$FIRST" == '  "bbbbbbbbbbbbbbb2"  "2026-10-22T08:00:00Z"  source_id="#12"'
DETAIL="out: $OUT"
check "two sources: a row is not printed without --rows" test "$(grep -c 'skipped the changelog' <<<"$OUT")" -eq 0

run "$R" --by producer,kind --rows
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "two keys: the first line names both" test "$(head -n 1 <<<"$OUT")" == "grouped by: producer, kind"
DETAIL="out: $OUT"
check "two keys: a group per pair of values" grep -qx 'producer="scanner/lint" kind="shadow": 1 row, 1 occurrence' <<<"$OUT"
DETAIL="out: $OUT"
check "two keys: a missing field is (none)" grep -qx 'producer=(none) kind="unused": 1 row, 1 occurrence' <<<"$OUT"
DETAIL="out: $OUT"
check "--rows: each member's row follows it" grep -q '^    {"obs_id":"bbbbbbbbbbbbbbb2".*"skipped the changelog"' <<<"$OUT"

# 2. --since keeps exactly the rows at or after it, fraction included.
new_repo
local_row "$R" '{"obs_id":"ccccccccccccccc1","ts":"2026-10-21T09:30:00Z","producer":"p"}'
local_row "$R" '{"obs_id":"ccccccccccccccc2","ts":"2026-10-21T09:30:00.5Z","producer":"p"}'
local_row "$R" '{"obs_id":"ccccccccccccccc3","ts":"2026-10-21T09:30:00.25Z","producer":"p"}'
run "$R" --since 2026-10-21T09:30:00.25Z
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "--since: the earlier rows in the same second are left out" grep -qx 'producer="p": 2 rows, 2 occurrences' <<<"$OUT"
DETAIL="out: $OUT"
check "--since: the row at since is kept" grep -q '"ccccccccccccccc3"' <<<"$OUT"
DETAIL="out: $OUT"
check "--since: the row before since is left out" test "$(grep -c '"ccccccccccccccc1"' <<<"$OUT")" -eq 0

# 3. Row values are printed escaped: ESC, a bidi override, a zero-width space and a C1 control.
new_repo
local_row "$R" "$(jq -cn '{obs_id: "ddddddddddddddd1", ts: "2026-10-21T09:30:00Z",
  producer: ("evil" + ([27] | implode) + "[2J" + ([8238] | implode) + "both" + ([8203] | implode)),
  source_id: ("x" + ([133] | implode) + "y")}')"
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "escaping: no raw ESC, C1, bidi or zero-width character is printed" \
  test "$(LC_ALL=C grep -c -e $'\x1b' -e $'\xc2\x85' -e $'\xe2\x80\xae' -e $'\xe2\x80\x8b' <<<"$OUT")" -eq 0
DETAIL="out: $OUT"
# The expected text is split so this file holds no escape sequence an editor could turn back into the character.
check "escaping: the escaped forms are printed" grep -qF 'producer="evil\u001b[2J\u''202eboth\u''200b"' <<<"$OUT"
DETAIL="out: $OUT"
check "escaping: a C1 control in source_id is printed escaped" grep -qF 'source_id="x\u''0085y"' <<<"$OUT"

# 4. An empty buffer.
new_repo
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "empty buffer: exits 0 and says no rows" test "$RC" -eq 0 -a "$(tail -n 1 <<<"$OUT")" == "no rows"

# 5. Usage.
for args in "--by a,b,c,d,e,f,g,h,i" "--by a.b" "--by a,a" "--by" "--since yesterday" "--bogus" "extra"; do
  # shellcheck disable=SC2086 # each case is a word list
  run "$R" $args
  DETAIL="exit $RC; stderr: $ERR"
  check "usage ($args): exits 2" test "$RC" -eq 2
done

# 6. A failed read fails the call with buffer.sh's exit and groups nothing.
mkdir -p "$TEST_TMPDIR/not-a-repo"
run "$TEST_TMPDIR/not-a-repo"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "outside a repository: exits 3 and prints nothing" test "$RC" -eq 3 -a -z "$OUT"
new_repo
local_row "$R" 'not json'
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "a line that is not JSON: exits non-zero and prints nothing" test "$RC" -ne 0 -a -z "$OUT"

# 7. A JSON line that is not an object passes buffer.sh's dedupe and is refused here.
new_repo
local_row "$R" '[1]'
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "a row that is not a JSON object: exits 1 and prints nothing" test "$RC" -eq 1 -a -z "$OUT"
DETAIL="stderr: $ERR"
check "a row that is not a JSON object: stderr says so" grep -q 'not a JSON object' <<<"$ERR"

printf '1..%d\n' "$CASE_NUM"
if [[ $FAILED -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi

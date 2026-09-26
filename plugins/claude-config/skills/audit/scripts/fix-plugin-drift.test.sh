#!/usr/bin/env bash
# Black-box contract tests for fix-plugin-drift.sh (self-contained, ships with the plugin).
# Uses --input <findings.json> to bypass the internal check invocation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fix-plugin-drift.sh"

# A POSIX-form base: a drive-letter TMPDIR such as C:/... carries a colon that
# splits PATH when a case builds a shim directory under it.
TMP_BASE="${TMPDIR:-/tmp}"
if command -v cygpath >/dev/null 2>&1; then
  TMP_BASE=$(cygpath -u "$TMP_BASE") || TMP_BASE="${TMPDIR:-/tmp}"
fi
# Guarded before the trap: a failed or empty mktemp must never reach a fixture
# write or the recursive delete below.
TEST_TMPDIR=$(mktemp -d "$TMP_BASE/fix-plugin-drift-test-XXXXXX") || TEST_TMPDIR=""
if [[ -z "$TEST_TMPDIR" || ! -d "$TEST_TMPDIR" ]]; then
  echo "ERROR: cannot create a temp directory under $TMP_BASE" >&2
  exit 2
fi
trap 'rm -rf "$TEST_TMPDIR"' EXIT
mkdir -p "$TEST_TMPDIR/tmp" "$TEST_TMPDIR/home/.claude"
export TMPDIR="$TEST_TMPDIR/tmp"
# Every case runs against a fixture user scope, never this machine's. Nothing
# writes a settings.json here: a case that needs a user file sets its own
# CLAUDE_CONFIG_DIR, so no case inherits another's `true`.
export HOME="$TEST_TMPDIR/home"
export CLAUDE_CONFIG_DIR="$TEST_TMPDIR/home/.claude"

FAILED=0
PASSED=0
SKIPPED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  PASSED=$((PASSED + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
# assert_jq <label> <file> <jq-predicate> - JSON is judged inside jq, never by
# a bash string compare.
assert_jq() {
  if jq -e "$3" "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1" "jq predicate false: $3"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}

# skip <case> <reason> - report a case the host cannot exercise. Deliberately
# does NOT call pass: a check that never ran is not a check that passed, and the
# tail's count is the number actually exercised.
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP: %s\n  reason: %s\n' "$1" "$2" >&2
}

# count_cr / count_lf <file> - carriage returns and line feeds in a file. Git
# Bash grep never matches a carriage return, so the count goes through tr; the
# arithmetic expansion strips the leading spaces BSD wc -c pads with.
count_cr() {
  local n
  n=$(tr -dc '\r' <"$1" | wc -c)
  echo "$((n))"
}
count_lf() {
  local n
  n=$(tr -dc '\n' <"$1" | wc -c)
  echo "$((n))"
}

# backup_count <dir> - how many settings.json.bak.<stamp>.<random> siblings
# exist. nullglob so an unmatched pattern counts 0 rather than 1 literal word.
backup_count() {
  local matches
  shopt -s nullglob
  matches=("$1"/settings.json.bak.*)
  shopt -u nullglob
  echo "${#matches[@]}"
}

# backup_path <dir> - the single backup sibling, or the empty string.
backup_path() {
  local matches
  shopt -s nullglob
  matches=("$1"/settings.json.bak.*)
  shopt -u nullglob
  echo "${matches[0]:-}"
}

# backup_shaped <path> - "yes" when the name is settings.json.bak.<UTC stamp>.<6 random>.
backup_shaped() {
  local re='^settings\.json\.bak\.[0-9]{8}T[0-9]{6}Z\.[A-Za-z0-9]{6}$'
  [[ "$(basename "$1")" =~ $re ]] && echo yes || echo no
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

make_case() {
  local case_dir="$TEST_TMPDIR/case-$CASE_NUM"
  mkdir -p "$case_dir"
  echo "$case_dir"
}

run_fix_dry() {
  local case_dir="$1"
  NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
    bash "$SCRIPT" --input "$case_dir/findings.json" 2>&1
}

run_fix_apply() {
  local case_dir="$1"
  NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
    bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1
}

# run_fix_internal <case-dir> [args...] - no --input, so the script runs
# check-plugin-drift.sh itself. The settings file is still pinned, so the check
# reads the fixture and never the machine's own configuration.
run_fix_internal() {
  local case_dir="$1"
  shift
  NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
    bash "$SCRIPT" "$@" 2>&1
}

# --- Case 1: no drift → no-op ---------------------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
echo '[{"key":"market1","status":"ok","skip_reason":"","orphans":[],"new_upstream":[],"renames":[]}]' >"$case_dir/findings.json"
echo '{"enabledPlugins":{"alpha@market1":true}}' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_dry "$case_dir") || exit_code=$?

assert_exit "case-1: no-op exit 0" 0 "$exit_code"
assert_contains "case-1: nothing-to-do msg" "$out" "No drift detected"

# --- Case 2: dry-run lists removals and report-only NEW without writing -----------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}
EOF

out=$(run_fix_dry "$case_dir") || true

assert_contains "case-2: AUTO-REMOVE shown" "$out" "AUTO-REMOVE"
assert_not_contains "case-2: no AUTO-ADD section" "$out" "AUTO-ADD"
assert_contains "case-2: NEW is report only" "$out" "NEW (report only) 1 upstream plugins with no entry in the settings file:"
assert_contains "case-2: removed listed" "$out" "removed@market1"
assert_contains "case-2: newcomer listed" "$out" "newcomer@market1"
assert_contains "case-2: dry-run notice" "$out" "Dry-run only"
assert_contains "case-2: a pending removal names what was not checked" "$out" \
  "Not checked: other developers' user scopes and managed settings."

unchanged=$(jq -e '.enabledPlugins["removed@market1"] == false' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-2: settings.json unchanged" "yes" "$unchanged"

# --- Case 3: --yes applies the removal and never adds NEW -------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}
EOF

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?

assert_exit "case-3: apply exit 0" 0 "$exit_code"
assert_contains "case-3: applied msg" "$out" "Applied:"

removed_absent=$(jq -e '.enabledPlugins | has("removed@market1") | not' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
alpha_preserved=$(jq -e '.enabledPlugins["alpha@market1"] == true' "$case_dir/settings.json" >/dev/null && echo yes || echo no)

assert_eq "case-3: orphan removed" "yes" "$removed_absent"
assert_jq "case-3: NEW is never added" "$case_dir/settings.json" '.enabledPlugins | has("newcomer@market1") | not'
assert_eq "case-3: existing entry preserved" "yes" "$alpha_preserved"
assert_contains "case-3: summary counts removals only" "$out" "Applied: 1 removals to $case_dir/settings.json"

# --- Case 4: true-orphan surfaced but NOT auto-removed ----------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "broken-but-enabled", "marketplace": "market1", "enabled": true}],
  "new_upstream": [],
  "renames": []
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "broken-but-enabled@market1": true
  }
}
EOF

out=$(run_fix_apply "$case_dir") || true

assert_contains "case-4: MANUAL REVIEW header" "$out" "MANUAL REVIEW"
assert_contains "case-4: lists the broken plugin" "$out" "broken-but-enabled@market1"

preserved=$(jq -e '.enabledPlugins["broken-but-enabled@market1"] == true' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-4: true-orphan preserved (not auto-removed)" "yes" "$preserved"

# --- Case 5: rename surfaced as advisory -------------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "old-name", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "old-name-renamed", "marketplace": "market1"}],
  "renames": [{"from": "old-name", "to": "old-name-renamed", "marketplace": "market1"}]
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "old-name@market1": false
  }
}
EOF

out=$(run_fix_dry "$case_dir") || true

assert_contains "case-5: RENAME advisory" "$out" "RENAME?"
assert_contains "case-5: pair shown" "$out" "old-name -> old-name-renamed"

# --- Case 6: dry-run with empty findings is a safe no-op --------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
echo '[]' >"$case_dir/findings.json"
echo 'not valid json' >"$case_dir/settings.json"

# fix-plugin-drift.sh does not validate settings.json on the dry-run path (no edit).
# The apply path validates. Dry-run reads findings.json only.
exit_code=0
out=$(run_fix_dry "$case_dir" 2>&1) || exit_code=$?

assert_exit "case-6: dry-run with empty findings exits 0" 0 "$exit_code"

# --- Case 7: jq-metacharacter plugin name is treated as data, not filter code ------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
evil='a"]) | halt_error | path(["b'
jq -n --arg evil "$evil" '[{
  key: "market1",
  status: "ok",
  skip_reason: "",
  orphans: [{name: $evil, marketplace: "market1", enabled: false}],
  new_upstream: [],
  renames: []
}]' >"$case_dir/findings.json"
jq -n --arg evil "$evil" '{enabledPlugins: {($evil + "@market1"): false, "alpha@market1": true}}' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?

assert_exit "case-7: apply with hostile name exits 0" 0 "$exit_code"
evil_absent=$(jq -e --arg evil "$evil" '.enabledPlugins | has($evil + "@market1") | not' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
alpha_preserved=$(jq -e '.enabledPlugins["alpha@market1"] == true' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-7: hostile-name entry removed literally" "yes" "$evil_absent"
assert_eq "case-7: other entries untouched (no filter injection)" "yes" "$alpha_preserved"

# --- Case 8: bare --input (no value) is a usage error, not a set -u crash ---------

CASE_NUM=$((CASE_NUM + 1))

exit_code=0
out=$(bash "$SCRIPT" --input 2>&1) || exit_code=$?

assert_exit "case-8: bare --input exits 2" 2 "$exit_code"
assert_contains "case-8: usage error message" "$out" "Missing value for --input"

# --- Case 9: a fatal internal check stops the run ---------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
echo 'not valid json' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_internal "$case_dir") || exit_code=$?

assert_exit "case-9: fatal check exits 2" 2 "$exit_code"
assert_contains "case-9: names the check and its status" "$out" "check-plugin-drift.sh failed with status 2"
assert_not_contains "case-9: never reports a clean bill of health" "$out" "No drift detected"

# --- Case 10: an apply leaves a backup of the pre-apply bytes ---------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
cat >"$case_dir/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}
EOF
# Named so the .bak glob cannot match it.
cp "$case_dir/settings.json" "$case_dir/settings.pre"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?

assert_exit "case-10: apply exit 0" 0 "$exit_code"
assert_eq "case-10: exactly one backup sibling" "1" "$(backup_count "$case_dir")"

bak=$(backup_path "$case_dir")
if [[ -n "$bak" ]] && cmp -s "$case_dir/settings.pre" "$bak"; then
  bak_match=yes
else
  bak_match=no
fi
assert_eq "case-10: backup holds the pre-apply bytes" "yes" "$bak_match"
assert_eq "case-10: backup is named settings.json.bak.<stamp>.<random>" "yes" "$(backup_shaped "$bak")"
assert_contains "case-10: summary names the backup" "$out" "(backup: $bak)"

# --- Case 11: the ladder resolving to the user settings file is refused -----------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/.claude"
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
cat >"$case_dir/.claude/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}
EOF
cp "$case_dir/.claude/settings.json" "$case_dir/settings.pre"

# No CLAUDE_SETTINGS_FILE, so the ladder resolves the path. GIT_DIR points at
# nothing, so `git rev-parse` fails and the ladder falls through to
# CLAUDE_PROJECT_DIR; CLAUDE_CONFIG_DIR makes that same directory the user
# scope, which is the collision the guard exists to refuse.
exit_code=0
out=$(NO_COLOR=1 \
  GIT_DIR=/nonexistent \
  CLAUDE_PROJECT_DIR="$case_dir" \
  CLAUDE_CONFIG_DIR="$case_dir/.claude" \
  bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1) || exit_code=$?

assert_contains "case-11: the ladder landed on the fixture" "$out" "Settings file: $case_dir/.claude/settings.json"
assert_exit "case-11: refuses with exit 2" 2 "$exit_code"
assert_contains "case-11: refusal names the ladder" "$out" "the project-root ladder resolved to the user settings file"

if cmp -s "$case_dir/settings.pre" "$case_dir/.claude/settings.json"; then
  untouched=yes
else
  untouched=no
fi
assert_eq "case-11: settings file byte-identical" "yes" "$untouched"
assert_eq "case-11: no backup created" "0" "$(backup_count "$case_dir/.claude")"

# --- Case 12b: a check that exits 0 without a document is still a pass ------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
echo '{}' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_internal "$case_dir") || exit_code=$?

assert_exit "case-12b: no declared marketplaces exits 0" 0 "$exit_code"
# The pass is only safe because the run says what it did. Both halves are
# asserted: the stderr NOTE, and the stdout line that must NOT borrow the
# wording of a completed audit.
assert_contains "case-12b: names the empty audit on stderr" "$out" "no marketplace was audited"
assert_contains "case-12b: stdout says nothing was audited" "$out" "No marketplace was audited"
assert_not_contains "case-12b: never claims a clean audit" "$out" "No drift detected"

# --- Case 12: an apply preserves the original's line-ending style -----------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
for variant in lf crlf stray; do
  mkdir -p "$case_dir/$variant"
  cat >"$case_dir/$variant/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
done

printf '{\n  "enabledPlugins": {\n    "alpha@market1": true,\n    "removed@market1": false\n  }\n}\n' \
  >"$case_dir/lf/settings.json"
printf '{\r\n  "enabledPlugins": {\r\n    "alpha@market1": true,\r\n    "removed@market1": false\r\n  }\r\n}\r\n' \
  >"$case_dir/crlf/settings.json"
# One stray CR as inter-token JSON whitespace in an otherwise LF file: cr is
# above 0 but below lf, so the file must stay on the LF branch.
printf '{\n  "enabledPlugins": {\r "alpha@market1": true,\n    "removed@market1": false\n  }\n}\n' \
  >"$case_dir/stray/settings.json"

cp "$case_dir/crlf/settings.json" "$case_dir/crlf/settings.pre"

# The exit code and the edit itself are asserted per variant. Without them the
# LF and CRLF line-ending assertions would also hold for an apply that aborted
# before writing anything, since those fixtures already carry the style they are
# checked for.
for variant in lf crlf stray; do
  variant_exit=0
  run_fix_apply "$case_dir/$variant" >/dev/null 2>&1 || variant_exit=$?
  assert_exit "case-12: $variant apply exit 0" 0 "$variant_exit"
  edited=$(jq -e '(.enabledPlugins | has("removed@market1") | not)
    and (.enabledPlugins | has("newcomer@market1") | not)
    and (.enabledPlugins["alpha@market1"] == true)' \
    "$case_dir/$variant/settings.json" >/dev/null 2>&1 && echo yes || echo no)
  assert_eq "case-12: $variant edit landed" "yes" "$edited"
done

assert_eq "case-12: LF fixture comes back with no CR" "0" "$(count_cr "$case_dir/lf/settings.json")"
assert_eq "case-12: stray-CR fixture stays on the LF branch" "0" "$(count_cr "$case_dir/stray/settings.json")"

crlf_cr=$(count_cr "$case_dir/crlf/settings.json")
crlf_lf=$(count_lf "$case_dir/crlf/settings.json")
if [[ "$crlf_cr" -gt 0 && "$crlf_cr" -eq "$crlf_lf" ]]; then
  crlf_ok=yes
else
  crlf_ok=no
fi
assert_eq "case-12: CRLF fixture comes back CRLF" "yes" "$crlf_ok"

bak=$(backup_path "$case_dir/crlf")
if [[ -n "$bak" ]] && cmp -s "$case_dir/crlf/settings.pre" "$bak"; then
  crlf_bak=yes
else
  crlf_bak=no
fi
assert_eq "case-12: CRLF backup holds the untouched original" "yes" "$crlf_bak"

# --- Case 13: an explicit path at the user settings file warns but applies --------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/.claude"
cat >"$case_dir/findings.json" <<'EOF'
[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]
EOF
cat >"$case_dir/.claude/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}
EOF

# CLAUDE_SETTINGS_FILE names the same file CLAUDE_CONFIG_DIR makes the user
# scope. The guard is waived because the path was given explicitly, so the run
# must apply, but it must say out loud that it waived it.
exit_code=0
out=$(NO_COLOR=1 \
  CLAUDE_CONFIG_DIR="$case_dir/.claude" \
  CLAUDE_SETTINGS_FILE="$case_dir/.claude/settings.json" \
  bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1) || exit_code=$?

assert_exit "case-13: explicit user-file target still applies" 0 "$exit_code"
assert_contains "case-13: warns that the guard was waived" "$out" "CLAUDE_SETTINGS_FILE points at the user settings file"
applied=$(jq -e '.enabledPlugins | has("removed@market1") | not' "$case_dir/.claude/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-13: the edit landed" "yes" "$applied"

# --- drift fixture shared by cases 14 to 16 --------------------------------------

DRIFT_FINDINGS='[{
  "key": "market1",
  "status": "ok",
  "skip_reason": "",
  "orphans": [{"name": "removed", "marketplace": "market1", "enabled": false}],
  "new_upstream": [{"name": "newcomer", "marketplace": "market1"}],
  "renames": []
}]'
SETTINGS_FIXTURE='{
  "enabledPlugins": {
    "alpha@market1": true,
    "removed@market1": false
  }
}'

# --- Case 14: a read-only settings file is applied, never falsely reported --------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"

# Is a read-only mode enforced here at all? On Windows `chmod 444` sets the
# read-only attribute and Git Bash does deny the write, but a share or a mount
# option can make mode bits advisory, and an assertion that cannot fail is
# worse than an absent one.
chmod 444 "$case_dir/settings.json"
if (printf 'x\n' >"$case_dir/settings.json") 2>/dev/null; then
  chmod 644 "$case_dir/settings.json"
  cp "$case_dir/settings.pre" "$case_dir/settings.json"
  skip "case-14: read-only settings file" "this host does not enforce a read-only mode, so the case cannot fail"
else
  exit_code=0
  out=$(run_fix_apply "$case_dir") || exit_code=$?

  # The hazard is a run that reports an edit it did not make. Either outcome is
  # acceptable on its own; the pairing is what must hold.
  if [[ "$exit_code" -eq 0 ]]; then
    applied=$(cmp -s "$case_dir/settings.pre" "$case_dir/settings.json" && echo no || echo yes)
    assert_eq "case-14: exit 0 means the file really changed" "yes" "$applied"
    assert_contains "case-14: reports the apply" "$out" "Applied:"
    landed=$(jq -e '(.enabledPlugins | has("removed@market1") | not)
      and (.enabledPlugins | has("newcomer@market1") | not)' \
      "$case_dir/settings.json" >/dev/null 2>&1 && echo yes || echo no)
    assert_eq "case-14: the edit is the one reported" "yes" "$landed"
  else
    unchanged=$(cmp -s "$case_dir/settings.pre" "$case_dir/settings.json" && echo yes || echo no)
    assert_eq "case-14: a refusal leaves the file byte-identical" "yes" "$unchanged"
    assert_not_contains "case-14: a refusal never reports an apply" "$out" "Applied:"
  fi
  chmod 644 "$case_dir/settings.json" 2>/dev/null
fi

# --- Cases 15 and 16: a signal ends the run, it does not just delete the temps ----

# signal_shim <dir> <signal> - a jq wrapper that signals the script the first
# time the post-edit validation runs, then execs the real jq. That validation is
# the first step after the stage exists, which is where an interrupted run used
# to carry on with its temporaries deleted and a stage still holding the
# original bytes.
signal_shim() {
  local dir="$1" sig="$2" real
  real=$(command -v jq)
  mkdir -p "$dir"
  # shellcheck disable=SC2016  # the shim's own source: these must stay literal
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in\n'
    printf '  *"type == \\"object\\""*)\n'
    printf '    if [[ -n "${SHIM_MARKER:-}" && ! -e "$SHIM_MARKER" ]]; then\n'
    printf '      : >"$SHIM_MARKER"\n'
    printf '      kill -%s "$PPID" 2>/dev/null\n' "$sig"
    printf '    fi\n'
    printf '    ;;\n'
    printf 'esac\n'
    printf 'exec %s "$@"\n' "$real"
  } >"$dir/jq"
  chmod +x "$dir/jq"
}

# run_signalled <case-dir> <signal> - an apply interrupted at that point.  # identifier, not prose # spellchecker:disable-line
run_signalled() {  # identifier, not prose # spellchecker:disable-line
  local case_dir="$1" sig="$2"
  signal_shim "$case_dir/shim" "$sig"
  PATH="$case_dir/shim:$PATH" \
    SHIM_MARKER="$case_dir/fired" \
    NO_COLOR=1 \
    CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
    bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1
}

for sig_case in "15 TERM 143" "16 INT 130"; do
  # shellcheck disable=SC2086  # three fixed fields, split on purpose
  set -- $sig_case
  sig_name="$2"
  sig_rc="$3"

  CASE_NUM=$((CASE_NUM + 1))
  case_dir=$(make_case)
  printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
  printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
  cp "$case_dir/settings.json" "$case_dir/settings.pre"

  exit_code=0
  out=$(run_signalled "$case_dir" "$sig_name") || exit_code=$?  # identifier, not prose # spellchecker:disable-line

  if [[ ! -e "$case_dir/fired" ]]; then
    skip "case-$1: SIG$sig_name during the apply" "the shim never fired, so the signal was never delivered"
  else
    assert_exit "case-$1: SIG$sig_name ends the run" "$sig_rc" "$exit_code"
    assert_not_contains "case-$1: SIG$sig_name never reports an apply" "$out" "Applied:"
    unchanged=$(cmp -s "$case_dir/settings.pre" "$case_dir/settings.json" && echo yes || echo no)
    assert_eq "case-$1: SIG$sig_name leaves the file byte-identical" "yes" "$unchanged"
    assert_eq "case-$1: SIG$sig_name leaves no backup behind" "0" "$(backup_count "$case_dir")"
  fi
done

# unchanged_since <case-dir> - "yes" when settings.json still equals settings.pre.
unchanged_since() {
  cmp -s "$1/settings.pre" "$1/settings.json" && echo yes || echo no
}

SKIPPED_BLOCK='{"key":"market2","status":"skipped","skip_reason":"fetch failed","orphans":[],"new_upstream":[],"renames":[]}'

# --- Case 17: every block skipped is reported as nothing audited ------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '[%s,{"key":"market3","status":"skipped","skip_reason":"no source.repo","orphans":[],"new_upstream":[],"renames":[]}]\n' \
  "$SKIPPED_BLOCK" >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"

for mode in dry apply; do
  exit_code=0
  out=$("run_fix_$mode" "$case_dir") || exit_code=$?
  assert_exit "case-17: $mode all-skipped exits 0" 0 "$exit_code"
  assert_contains "case-17: $mode says nothing was audited" "$out" "No marketplace was audited, so there is nothing to report."
  assert_contains "case-17: $mode SKIPPED header" "$out" "SKIPPED 2 marketplaces not audited:"
  assert_contains "case-17: $mode lists market2 with its reason" "$out" "  - market2 (fetch failed)"
  assert_contains "case-17: $mode lists market3 with its reason" "$out" "  - market3 (no source.repo)"
  assert_not_contains "case-17: $mode never claims a clean audit" "$out" "No drift detected"
  assert_eq "case-17: $mode settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
  assert_eq "case-17: $mode no backup" "0" "$(backup_count "$case_dir")"
done

# --- Case 18: a partly skipped run lists the skipped block beside the result ------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/clean" "$case_dir/drift"
printf '[{"key":"market1","status":"ok","skip_reason":"","orphans":[],"new_upstream":[],"renames":[]},%s]\n' \
  "$SKIPPED_BLOCK" >"$case_dir/clean/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/clean/settings.json"
printf '%s' "$DRIFT_FINDINGS" | jq --argjson s "$SKIPPED_BLOCK" '. + [$s]' >"$case_dir/drift/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/drift/settings.json"

out=$(run_fix_dry "$case_dir/clean") || true
assert_contains "case-18: clean run still says no drift" "$out" "No drift detected"
assert_contains "case-18: clean run lists the skipped key" "$out" "  - market2 (fetch failed)"
before_verdict="${out%%No drift detected*}"
assert_contains "case-18: SKIPPED section sits above the verdict" "$before_verdict" "SKIPPED 1 marketplaces not audited:"

out=$(run_fix_dry "$case_dir/drift") || true
assert_contains "case-18: drift run renders the plan" "$out" "AUTO-REMOVE"
before_plan="${out%%AUTO-REMOVE*}"
assert_contains "case-18: SKIPPED section sits above the plan" "$before_plan" "  - market2 (fetch failed)"

# --- Case 19: a plan the file already satisfies has nothing to apply --------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
# Compact, so a jq round trip would change the bytes even with no edit in it.
# The removal's key is already absent; NEW is never a pending edit.
printf '{"enabledPlugins":{"alpha@market1":true}}\n' >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-19: no-op apply exits 0" 0 "$exit_code"
assert_contains "case-19: says nothing to apply" "$out" "Nothing to apply (no pending removal)."
assert_contains "case-19: counts the filtered entry" "$out" "FILTERED 1 plan entries no longer match the settings file"
assert_not_contains "case-19: never reports an apply" "$out" "Applied"
assert_not_contains "case-19: never reaches the stage-equals-current refusal" "$out" "staged replacement is identical"
assert_eq "case-19: settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
assert_eq "case-19: no backup" "0" "$(backup_count "$case_dir")"

out=$(run_fix_dry "$case_dir") || true
assert_contains "case-19: dry run says nothing to apply" "$out" "Nothing to apply (no pending removal)."
assert_not_contains "case-19: dry run never asks for --yes" "$out" "Re-run with"

# --- Case 20: a remove whose key is now true goes to manual review ---------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '{"enabledPlugins":{"alpha@market1":true,"removed@market1":true}}\n' >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-20: apply exits 0" 0 "$exit_code"
assert_contains "case-20: stale-true remove counted as filtered" "$out" "FILTERED 1 plan entries no longer match the settings file"
assert_contains "case-20: MANUAL REVIEW section present" "$out" "MANUAL REVIEW"
assert_not_contains "case-20: the moved removal leaves no AUTO-REMOVE section" "$out" "AUTO-REMOVE"
manual_section="${out#*MANUAL REVIEW}"
assert_contains "case-20: stale-true remove listed under MANUAL REVIEW" "$manual_section" "removed@market1 (now true in this file)"
assert_contains "case-20: nothing left to apply" "$out" "Nothing to apply (no pending removal)."
assert_not_contains "case-20: never reports an apply" "$out" "Applied"
assert_eq "case-20: settings byte-identical" "yes" "$(unchanged_since "$case_dir")"

# --- Case 21: a findings list jq cannot read is fatal ----------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
for bad in "orphans:orphan removals" "renames:renames"; do
  field="${bad%%:*}"
  label="${bad#*:}"
  printf '%s' "$DRIFT_FINDINGS" | jq --arg f "$field" '.[0][$f] = "x"' >"$case_dir/findings.json"
  printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
  cp "$case_dir/settings.json" "$case_dir/settings.pre"
  exit_code=0
  out=$(run_fix_apply "$case_dir") || exit_code=$?
  assert_exit "case-21: bad $field exits 2" 2 "$exit_code"
  assert_contains "case-21: bad $field names the list" "$out" "ERROR: cannot read the $label list from the findings JSON"
  assert_not_contains "case-21: bad $field never reports an apply" "$out" "Applied"
  assert_eq "case-21: bad $field settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
  assert_eq "case-21: bad $field no backup" "0" "$(backup_count "$case_dir")"
done

# --- Case 22: findings that are not an array of blocks are refused ---------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"
for shape in object string empty element multi; do
  case "$shape" in
  object) printf '{"not":"an array"}\n' >"$case_dir/findings.json" ;;
  # Two documents: jq -e alone would judge only the trailing array.
  multi) printf '{"x":%s}\n[]\n' "$(printf '%s' "$DRIFT_FINDINGS" | jq -c '.[0]')" >"$case_dir/findings.json" ;;
  string) printf '"text"\n' >"$case_dir/findings.json" ;;
  element) printf '[1]\n' >"$case_dir/findings.json" ;;
  *) : >"$case_dir/findings.json" ;;
  esac
  exit_code=0
  out=$(run_fix_apply "$case_dir") || exit_code=$?
  assert_exit "case-22: $shape input exits 2" 2 "$exit_code"
  assert_not_contains "case-22: $shape input never claims a clean audit" "$out" "No drift detected"
  assert_eq "case-22: $shape settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
done

# --- Case 23: a settings file changed under the run is refused -------------------

# concurrent_shim <dir> - a jq wrapper that, the first time the post-edit
# validation runs, overwrites the settings file with another writer's bytes.
concurrent_shim() {
  local dir="$1" real
  real=$(command -v jq)
  mkdir -p "$dir"
  # shellcheck disable=SC2016  # the shim's own source: these must stay literal
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in\n'
    printf '  *"type == \\"object\\""*)\n'
    printf '    if [[ -n "${SHIM_MARKER:-}" && ! -e "$SHIM_MARKER" ]]; then\n'
    printf '      : >"$SHIM_MARKER"\n'
    printf '      cat "$SHIM_WRITE" >"$SHIM_TARGET"\n'
    printf '    fi\n'
    printf '    ;;\n'
    printf 'esac\n'
    printf 'exec %s "$@"\n' "$real"
  } >"$dir/jq"
  chmod +x "$dir/jq"
}

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
printf '{"enabledPlugins":{"alpha@market1":true,"removed@market1":false,"other@market9":true}}\n' \
  >"$case_dir/concurrent.json"
concurrent_shim "$case_dir/shim"

exit_code=0
out=$(PATH="$case_dir/shim:$PATH" \
  SHIM_MARKER="$case_dir/fired" \
  SHIM_WRITE="$case_dir/concurrent.json" \
  SHIM_TARGET="$case_dir/settings.json" \
  NO_COLOR=1 \
  CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
  bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1) || exit_code=$?

if [[ ! -e "$case_dir/fired" ]]; then
  skip "case-23: concurrent write during the apply" "the shim never fired, so no concurrent write happened"
else
  assert_exit "case-23: a changed settings file exits 2" 2 "$exit_code"
  assert_contains "case-23: names the concurrent change" "$out" "changed after the plan was computed"
  assert_not_contains "case-23: never reports an apply" "$out" "Applied"
  kept=$(cmp -s "$case_dir/concurrent.json" "$case_dir/settings.json" && echo yes || echo no)
  assert_eq "case-23: the other writer's bytes survive" "yes" "$kept"
  assert_eq "case-23: no backup" "0" "$(backup_count "$case_dir")"
fi

# --- Case 24: a missing enabledPlugins filters as empty; a non-object is fatal ----

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '{"model":"x"}\n' >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-24: no enabledPlugins exits 0" 0 "$exit_code"
assert_contains "case-24: the absent removal is filtered" "$out" "FILTERED 1 plan entries no longer match the settings file"
assert_eq "case-24: no enabledPlugins settings byte-identical" "yes" "$(unchanged_since "$case_dir")"

# A pending removal is what reaches the filter, so the fatal path is exercised.
mkdir -p "$case_dir/nonobj"
cp "$case_dir/findings.json" "$case_dir/nonobj/findings.json"
printf '{"enabledPlugins":["not","an","object"]}\n' >"$case_dir/nonobj/settings.json"
cp "$case_dir/nonobj/settings.json" "$case_dir/nonobj/settings.pre"
for mode in dry apply; do
  exit_code=0
  out=$("run_fix_$mode" "$case_dir/nonobj") || exit_code=$?
  assert_exit "case-24: $mode non-object enabledPlugins exits 2" 2 "$exit_code"
  assert_eq "case-24: $mode non-object settings byte-identical" "yes" "$(unchanged_since "$case_dir/nonobj")"
done
assert_eq "case-24: non-object no backup" "0" "$(backup_count "$case_dir/nonobj")"

# --- Case 25: an unreadable settings file with a pending plan is fatal on dry run -

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
echo 'not valid json' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_dry "$case_dir") || exit_code=$?
assert_exit "case-25: dry run exits 2" 2 "$exit_code"
assert_contains "case-25: names the settings file" "$out" "ERROR: cannot read $case_dir/settings.json to filter the plan against it"
assert_not_contains "case-25: never asks for --yes" "$out" "Re-run with"

# --- Case 26: NEW alone is report only, even with --yes ---------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '[{"key":"market1","status":"ok","skip_reason":"","orphans":[],"new_upstream":[{"name":"newcomer","marketplace":"market1"}],"renames":[]}]\n' \
  >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"

for mode in dry apply; do
  exit_code=0
  out=$("run_fix_$mode" "$case_dir") || exit_code=$?
  assert_exit "case-26: $mode NEW-only exits 0" 0 "$exit_code"
  assert_contains "case-26: $mode lists NEW as report only" "$out" "NEW (report only) 1 upstream plugins"
  assert_contains "case-26: $mode says nothing to apply" "$out" "Nothing to apply (no pending removal)."
  assert_not_contains "case-26: $mode never names what was not checked without a removal" "$out" "Not checked:"
  assert_eq "case-26: $mode settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
  assert_eq "case-26: $mode no backup" "0" "$(backup_count "$case_dir")"
done

# --- Case 27: control characters in a displayed entry never reach the terminal ---

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
esc_name=$'evil\e]0;title\anext'
jq -n --arg n "$esc_name" '[
  {key: "market1", status: "ok", skip_reason: "", orphans: [{name: $n, marketplace: "market1", enabled: false}],
   new_upstream: [{name: ("new" + $n), marketplace: "market1"}], renames: []},
  {key: ("mk" + $n), status: "skipped", skip_reason: ("why" + $n), orphans: [], new_upstream: [], renames: []}
]' >"$case_dir/findings.json"
jq -n --arg n "$esc_name" '{enabledPlugins: {($n + "@market1"): false, "alpha@market1": true}}' >"$case_dir/settings.json"

out=$(run_fix_dry "$case_dir") || true
assert_contains "case-27: plan shows the removal with ? for control chars" "$out" "  - evil?]0;title?next@market1"
assert_contains "case-27: plan shows the NEW name with ? for control chars" "$out" "  - newevil?]0;title?next@market1"
assert_contains "case-27: SKIPPED listing shows ? for control chars" "$out" "  - mkevil?]0;title?next (whyevil?]0;title?next)"
if [[ "$out" == *$'\e'* || "$out" == *$'\a'* ]]; then raw_ctl=yes; else raw_ctl=no; fi
assert_eq "case-27: no raw ESC or BEL byte in the output" "no" "$raw_ctl"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-27: apply exits 0" 0 "$exit_code"
assert_jq "case-27: the edit removed the raw key and nothing else" "$case_dir/settings.json" \
  '.enabledPlugins == {"alpha@market1": true}'

# --- Case 28: a skipped block with no reason says so ------------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '[{"key":"market4","status":"skipped","orphans":[],"new_upstream":[],"renames":[]}]\n' >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"

out=$(run_fix_dry "$case_dir") || true
assert_contains "case-28: missing reason is named" "$out" "  - market4 (no reason given)"

# --- Cases 29 and 30: a path at the old backup name is never written or removed ---

# date_shim <dir> - a clock that always reads one stamp, so the backup name is
# known in advance. With SHIM_SETTINGS set it also plays another writer and
# rewrites that file when the clock is read, which is after the plan is fixed.
date_shim() {
  local dir="$1"
  mkdir -p "$dir"
  # shellcheck disable=SC2016  # the shim's own source: these must stay literal
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [[ -n "${SHIM_SETTINGS:-}" ]]; then\n'
    printf '  printf %s "{\\"enabledPlugins\\":{\\"removed@market1\\":false,\\"other@market9\\":true}}" >"$SHIM_SETTINGS"\n' "'%s\n'"
    printf 'fi\n'
    printf 'printf %s\n' "'20260925T000000Z\n'"
  } >"$dir/date"
  chmod +x "$dir/date"
}

# link_to_null <path> - a symlink to /dev/null, or nothing when this host's ln
# makes a copy instead (Git Bash without native symlinks). The caller checks -L.
link_to_null() {
  MSYS=winsymlinks:nativestrict ln -s /dev/null "$1" 2>/dev/null || ln -s /dev/null "$1" 2>/dev/null || true
}

# old_backup_intact <kind> <path> <reference> - "yes" when the pre-existing
# path is still the same kind of thing: a regular file with its bytes, a
# directory, or a symlink.
old_backup_intact() {
  case "$1" in
  file) [[ -f "$2" && ! -L "$2" ]] && cmp -s "$3" "$2" && echo yes || echo no ;;
  dir) [[ -d "$2" && ! -L "$2" ]] && echo yes || echo no ;;
  *) [[ -L "$2" ]] && echo yes || echo no ;;
  esac
}

for backup_case in "29 quiet" "30 concurrent"; do
  # shellcheck disable=SC2086  # two fixed fields, split on purpose
  set -- $backup_case
  case_no="$1"
  run_kind="$2"
  CASE_NUM=$((CASE_NUM + 1))
  for kind in file dir link; do
    case_dir="$(make_case)/$kind"
    mkdir -p "$case_dir"
    printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
    printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
    date_shim "$case_dir/shim"
    # The name the previous release wrote for the shimmed stamp.
    old_bak="$case_dir/settings.json.20260925T000000Z.bak"
    printf 'decoy\n' >"$case_dir/decoy.ref"
    case "$kind" in
    file) cp "$case_dir/decoy.ref" "$old_bak" ;;
    dir) mkdir -p "$old_bak" ;;
    *) link_to_null "$old_bak" ;;
    esac
    if [[ "$kind" == link && ! -L "$old_bak" ]]; then
      skip "case-$case_no: $run_kind run beside a symlink at the old backup name" "ln -s did not make a real symlink on this host"
      continue
    fi
    if [[ "$run_kind" == concurrent ]]; then
      shim_settings="$case_dir/settings.json"
    else
      shim_settings=""
    fi
    cp "$case_dir/settings.json" "$case_dir/settings.pre"
    exit_code=0
    out=$(PATH="$case_dir/shim:$PATH" \
      SHIM_SETTINGS="$shim_settings" \
      NO_COLOR=1 \
      CLAUDE_SETTINGS_FILE="$case_dir/settings.json" \
      bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1) || exit_code=$?
    label="case-$case_no: $run_kind run beside a $kind at the old backup name"
    assert_eq "$label leaves it intact" "yes" "$(old_backup_intact "$kind" "$old_bak" "$case_dir/decoy.ref")"
    if [[ "$run_kind" == concurrent ]]; then
      assert_exit "$label refuses with exit 2" 2 "$exit_code"
      assert_not_contains "$label never reports an apply" "$out" "Applied"
      assert_jq "$label keeps the other writer's bytes" "$case_dir/settings.json" '.enabledPlugins["other@market9"] == true'
      assert_eq "$label removes its own backup" "0" "$(backup_count "$case_dir")"
    else
      assert_exit "$label applies" 0 "$exit_code"
      assert_eq "$label writes exactly one new backup" "1" "$(backup_count "$case_dir")"
      bak=$(backup_path "$case_dir")
      assert_eq "$label names it with the stamp and a random suffix" "yes" "$(backup_shaped "$bak")"
      assert_contains "$label backup uses the shimmed stamp" "$bak" "settings.json.bak.20260925T000000Z."
      bak_ok=$([[ -n "$bak" ]] && cmp -s "$case_dir/settings.pre" "$bak" && echo yes || echo no)
      assert_eq "$label backup holds the pre-apply bytes" "yes" "$bak_ok"
    fi
  done
done

# --- Case 31: a carriage return inside a plugin name is part of the key ----------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
cr_name=$'cr\rname'
jq -n --arg n "$cr_name" '[{key: "market1", status: "ok", skip_reason: "",
  orphans: [{name: $n, marketplace: "market1", enabled: false}],
  new_upstream: [{name: ("new" + $n), marketplace: "market1"}], renames: []}]' >"$case_dir/findings.json"
jq -n --arg n "$cr_name" '{enabledPlugins: {($n + "@market1"): false, "crname@market1": false, "alpha@market1": true}}' \
  >"$case_dir/settings.json"

out=$(run_fix_dry "$case_dir") || true
assert_contains "case-31: the CR displays as ?" "$out" "cr?name@market1"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-31: apply exits 0" 0 "$exit_code"
assert_contains "case-31: the removal applied" "$out" "Applied: 1 removals"
assert_jq "case-31: only the exact CR-bearing key is removed, nothing is added" "$case_dir/settings.json" \
  '.enabledPlugins == {"crname@market1": false, "alpha@market1": true}'

# --- Case 32: CR-bearing marketplace and plugin keys, check then fix, end to end --

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/.claude" "$case_dir/.claude-plugin"
# A directory-source marketplace, because NTFS refuses a carriage return in a
# fixture file name. `gone@mk` names a marketplace the file does not declare,
# and `dup@mk\r` is in the catalog: both carry a name the CR-bearing orphans
# share without the CR, and both must survive.
printf '%s\n' '{
  "enabledPlugins": {
    "alpha@mk\r": true,
    "gone@mk\r": false,
    "gone@mk": false,
    "dup\r@mk\r": false,
    "dup@mk\r": true
  },
  "extraKnownMarketplaces": {"mk\r": {"source": {"source": "directory", "path": "./"}}}
}' >"$case_dir/.claude/settings.json"
printf '%s\n' '{"name": "mk", "plugins": [{"name": "alpha"}, {"name": "dup"}]}' \
  >"$case_dir/.claude-plugin/marketplace.json"

exit_code=0
out=$(NO_COLOR=1 CLAUDE_SETTINGS_FILE="$case_dir/.claude/settings.json" \
  bash "$SCRIPT" --yes 2>&1) || exit_code=$?
assert_exit "case-32: check then apply exits 0" 0 "$exit_code"
assert_contains "case-32: both CR-bearing orphans removed" "$out" "Applied: 2 removals"
assert_jq "case-32: exactly the CR-bearing orphan keys are gone" "$case_dir/.claude/settings.json" \
  '(.enabledPlugins | keys) == (["alpha@mk\r", "dup@mk\r", "gone@mk"] | sort)'

# --- Case 33: a key holding = and / is removed exactly, end to end ---------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/fixtures"
printf '%s\n' '{
  "enabledPlugins": {"k=/x@market1": false, "k@market1": false, "alpha@market1": true},
  "extraKnownMarketplaces": {"market1": {"source": {"source": "github", "repo": "owner/market1"}}}
}' >"$case_dir/settings.json"
printf '%s\n' '{"name": "market1", "plugins": [{"name": "alpha"}, {"name": "k"}]}' >"$case_dir/fixtures/market1.json"

exit_code=0
out=$(SETTINGS_AUDIT_FIXTURE_DIR="$case_dir/fixtures" run_fix_internal "$case_dir" --yes) || exit_code=$?
assert_exit "case-33: check then apply exits 0" 0 "$exit_code"
assert_contains "case-33: one removal" "$out" "Applied: 1 removals"
assert_jq "case-33: only the = and / key is removed" "$case_dir/settings.json" \
  '.enabledPlugins == {"k@market1": false, "alpha@market1": true}'

# --- Case 34: a true in the user settings file holds the removal -----------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/user"
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"
printf '{"enabledPlugins":{"removed@market1":true}}\n' >"$case_dir/user/settings.json"

for mode in dry apply; do
  exit_code=0
  out=$(CLAUDE_CONFIG_DIR="$case_dir/user" "run_fix_$mode" "$case_dir") || exit_code=$?
  assert_exit "case-34: $mode exits 0" 0 "$exit_code"
  manual_section="${out#*MANUAL REVIEW}"
  assert_contains "case-34: $mode moves the removal to MANUAL REVIEW" "$manual_section" \
    "removed@market1 (true in a lower-precedence scope file; removing this entry would enable it)"
  assert_not_contains "case-34: $mode no AUTO-REMOVE section" "$out" "AUTO-REMOVE"
  assert_contains "case-34: $mode nothing to apply" "$out" "Nothing to apply (no pending removal)."
  assert_eq "case-34: $mode settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
  assert_eq "case-34: $mode no backup" "0" "$(backup_count "$case_dir")"
done

# --- Case 35: a true in settings.local.json does not hold a project removal ------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/user"
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
printf '{"enabledPlugins":{"removed@market1":true}}\n' >"$case_dir/settings.local.json"
printf '{"enabledPlugins":{"removed@market1":false}}\n' >"$case_dir/user/settings.json"

exit_code=0
out=$(CLAUDE_CONFIG_DIR="$case_dir/user" run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-35: apply exits 0" 0 "$exit_code"
assert_contains "case-35: the removal applies" "$out" "Applied: 1 removals"
assert_contains "case-35: names the user file it checked" "$out" \
  "Checked for a true this removal would expose: $case_dir/user/settings.json"
assert_contains "case-35: says what it did not check" "$out" \
  "Not checked: other developers' user scopes and managed settings."
assert_jq "case-35: the orphan is gone" "$case_dir/settings.json" '.enabledPlugins | has("removed@market1") | not'

# --- Case 36: a user file that cannot be checked fails closed --------------------

CASE_NUM=$((CASE_NUM + 1))
for variant in invalid nonobject directory; do
  case_dir="$(make_case)/$variant"
  mkdir -p "$case_dir/user"
  printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
  printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.json"
  cp "$case_dir/settings.json" "$case_dir/settings.pre"
  case "$variant" in
  invalid) printf 'not json\n' >"$case_dir/user/settings.json" ;;
  nonobject) printf '{"enabledPlugins":["removed@market1"]}\n' >"$case_dir/user/settings.json" ;;
  *) mkdir -p "$case_dir/user/settings.json" ;;
  esac
  for mode in dry apply; do
    exit_code=0
    out=$(CLAUDE_CONFIG_DIR="$case_dir/user" "run_fix_$mode" "$case_dir") || exit_code=$?
    assert_exit "case-36: $variant $mode exits 0" 0 "$exit_code"
    assert_contains "case-36: $variant $mode says the removals are held" "$out" \
      "so every orphan removal is held for manual review."
    assert_contains "case-36: $variant $mode lists the held removal" "$out" \
      "removed@market1 (a lower-precedence scope file could not be checked)"
    assert_eq "case-36: $variant $mode settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
  done
done

# --- Case 37: an audited settings.local.json is held by its sibling's true -------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
mkdir -p "$case_dir/user" "$case_dir/free"
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/settings.local.json"
cp "$case_dir/settings.local.json" "$case_dir/local.pre"
printf '{"enabledPlugins":{"removed@market1":true}}\n' >"$case_dir/settings.json"

exit_code=0
out=$(NO_COLOR=1 CLAUDE_CONFIG_DIR="$case_dir/user" CLAUDE_SETTINGS_FILE="$case_dir/settings.local.json" \
  bash "$SCRIPT" --input "$case_dir/findings.json" --yes 2>&1) || exit_code=$?
assert_exit "case-37: held local apply exits 0" 0 "$exit_code"
assert_contains "case-37: the sibling's true holds the removal" "$out" \
  "removed@market1 (true in a lower-precedence scope file; removing this entry would enable it)"
local_same=$(cmp -s "$case_dir/local.pre" "$case_dir/settings.local.json" && echo yes || echo no)
assert_eq "case-37: settings.local.json byte-identical" "yes" "$local_same"

# Without the sibling's true, the same local file's removal applies.
cp "$case_dir/findings.json" "$case_dir/free/findings.json"
printf '%s\n' "$SETTINGS_FIXTURE" >"$case_dir/free/settings.local.json"
printf '{"enabledPlugins":{"removed@market1":false}}\n' >"$case_dir/free/settings.json"
exit_code=0
out=$(NO_COLOR=1 CLAUDE_CONFIG_DIR="$case_dir/user" CLAUDE_SETTINGS_FILE="$case_dir/free/settings.local.json" \
  bash "$SCRIPT" --input "$case_dir/free/findings.json" --yes 2>&1) || exit_code=$?
assert_exit "case-37: free local apply exits 0" 0 "$exit_code"
assert_jq "case-37: the free local removal landed" "$case_dir/free/settings.local.json" \
  '.enabledPlugins | has("removed@market1") | not'

# --- Final ------------------------------------------------------------------

printf '\nPASS %d, FAIL %d, SKIP %d\n' "$PASSED" "$FAILED" "$SKIPPED"
if [[ "$FAILED" -eq 0 ]]; then
  printf 'All %d checks passed.\n' "$PASSED"
  exit 0
fi
printf '%d/%d checks failed.\n' "$FAILED" "$((PASSED + FAILED))" >&2
exit 1

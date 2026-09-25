#!/usr/bin/env bash
# Black-box contract tests for fix-plugin-drift.sh (self-contained — ships with the plugin).
# Uses --input <findings.json> to bypass the internal check invocation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fix-plugin-drift.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
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

# backup_count <dir> - how many settings.json.<stamp>.bak siblings exist.
# nullglob so an unmatched pattern counts 0 rather than 1 literal word.
backup_count() {
  local matches
  shopt -s nullglob
  matches=("$1"/settings.json.*.bak)
  shopt -u nullglob
  echo "${#matches[@]}"
}

# backup_path <dir> - the single backup sibling, or the empty string.
backup_path() {
  local matches
  shopt -s nullglob
  matches=("$1"/settings.json.*.bak)
  shopt -u nullglob
  echo "${matches[0]:-}"
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

# --- Case 2: dry-run lists removals + adds without writing ------------------------

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
assert_contains "case-2: AUTO-ADD shown" "$out" "AUTO-ADD"
assert_contains "case-2: removed listed" "$out" "removed@market1"
assert_contains "case-2: newcomer listed" "$out" "newcomer@market1"
assert_contains "case-2: dry-run notice" "$out" "Dry-run only"

unchanged=$(jq -e '.enabledPlugins["removed@market1"] == false' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-2: settings.json unchanged" "yes" "$unchanged"

# --- Case 3: --yes applies removal + addition atomically --------------------------

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
newcomer_present=$(jq -e '.enabledPlugins["newcomer@market1"] == false' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
alpha_preserved=$(jq -e '.enabledPlugins["alpha@market1"] == true' "$case_dir/settings.json" >/dev/null && echo yes || echo no)

assert_eq "case-3: orphan removed" "yes" "$removed_absent"
assert_eq "case-3: new added as false" "yes" "$newcomer_present"
assert_eq "case-3: existing entry preserved" "yes" "$alpha_preserved"

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
assert_contains "case-10: summary names the backup" "$out" ".bak"

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
    and (.enabledPlugins["newcomer@market1"] == false)
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
      and (.enabledPlugins["newcomer@market1"] == false)' \
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
printf '{"enabledPlugins":{"alpha@market1":true,"newcomer@market1":false}}\n' >"$case_dir/settings.json"
cp "$case_dir/settings.json" "$case_dir/settings.pre"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-19: no-op apply exits 0" 0 "$exit_code"
assert_contains "case-19: says nothing to apply" "$out" "Nothing to apply (no pending removal or addition)."
assert_contains "case-19: counts the filtered entries" "$out" "FILTERED 2 plan entries no longer match the settings file"
assert_not_contains "case-19: never reports an apply" "$out" "Applied"
assert_not_contains "case-19: never reaches the stage-equals-current refusal" "$out" "staged replacement is identical"
assert_eq "case-19: settings byte-identical" "yes" "$(unchanged_since "$case_dir")"
assert_eq "case-19: no backup" "0" "$(backup_count "$case_dir")"

out=$(run_fix_dry "$case_dir") || true
assert_contains "case-19: dry run says nothing to apply" "$out" "Nothing to apply (no pending removal or addition)."
assert_not_contains "case-19: dry run never asks for --yes" "$out" "Re-run with"

# --- Case 20: a remove whose key is now true goes to manual review ---------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '{"enabledPlugins":{"alpha@market1":true,"removed@market1":true}}\n' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-20: apply exits 0" 0 "$exit_code"
assert_contains "case-20: stale-true remove counted as filtered" "$out" "FILTERED 1 plan entries no longer match the settings file"
manual_section="${out#*MANUAL REVIEW}"
assert_contains "case-20: stale-true remove listed under MANUAL REVIEW" "$manual_section" "removed@market1"
assert_contains "case-20: only the addition is applied" "$out" "Applied: 0 removals, 1 additions"
still_true=$(jq -e '.enabledPlugins["removed@market1"] == true and .enabledPlugins["newcomer@market1"] == false' \
  "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-20: the true entry is kept, the addition landed" "yes" "$still_true"

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
for shape in object string empty element; do
  case "$shape" in
  object) printf '{"not":"an array"}\n' >"$case_dir/findings.json" ;;
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
  assert_not_contains "case-23: never reports an apply" "$out" "Applied"
  kept=$(cmp -s "$case_dir/concurrent.json" "$case_dir/settings.json" && echo yes || echo no)
  assert_eq "case-23: the other writer's bytes survive" "yes" "$kept"
  assert_eq "case-23: no backup" "0" "$(backup_count "$case_dir")"
fi

# --- Case 24: a missing enabledPlugins filters as empty; a non-object is fatal ----

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '[{"key":"market1","status":"ok","skip_reason":"","orphans":[],"new_upstream":[{"name":"newcomer","marketplace":"market1"}],"renames":[]}]\n' \
  >"$case_dir/findings.json"
printf '{"model":"x"}\n' >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-24: no enabledPlugins applies" 0 "$exit_code"
added=$(jq -e '.enabledPlugins["newcomer@market1"] == false' "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-24: NEW entry survives the filter and lands" "yes" "$added"

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

# --- Case 26: an add whose key is already true is dropped ------------------------

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(make_case)
printf '%s\n' "$DRIFT_FINDINGS" >"$case_dir/findings.json"
printf '{"enabledPlugins":{"alpha@market1":true,"removed@market1":false,"newcomer@market1":true}}\n' \
  >"$case_dir/settings.json"

exit_code=0
out=$(run_fix_apply "$case_dir") || exit_code=$?
assert_exit "case-26: apply exits 0" 0 "$exit_code"
assert_contains "case-26: the existing add is counted as filtered" "$out" "FILTERED 1 plan entries no longer match the settings file"
assert_contains "case-26: only the removal is applied" "$out" "Applied: 1 removals, 0 additions"
kept_true=$(jq -e '.enabledPlugins["newcomer@market1"] == true and (.enabledPlugins | has("removed@market1") | not)' \
  "$case_dir/settings.json" >/dev/null && echo yes || echo no)
assert_eq "case-26: the true entry is not flipped to false" "yes" "$kept_true"

# --- Final ------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1

#!/usr/bin/env bash
# Tests for parse-branch-issue.sh.
# Each case: PASS prints, FAIL prints. Non-zero exit on any FAIL.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="${SCRIPT_DIR}/parse-branch-issue.sh"

if [[ ! -x "$PARSER" ]]; then
  echo "FAIL: parser missing or not executable: $PARSER" >&2
  exit 1
fi

PASS=0
FAIL=0

# Isolate every case from ambient config: an empty fixture HOME and repo root,
# and no exported userConfig value, unless a case sets its own.
FIXTURES="$(mktemp -d)"
trap 'rm -rf "$FIXTURES"' EXIT
export HOME="${FIXTURES}/empty-home"
export CLAUDE_PROJECT_DIR="${FIXTURES}/empty-repo"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
unset CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN

run_test() {
  local desc="$1" input="$2" expected_out="$3" expected_exit="$4" pattern="${5:-}"
  local actual_out actual_exit
  actual_out=$(bash "$PARSER" "$input" "$pattern" 2>/dev/null)
  actual_exit=$?
  if [[ "$actual_out" == "$expected_out" && "$actual_exit" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       input='$input'"
    echo "       got     out='$actual_out' exit=$actual_exit"
    echo "       wanted  out='$expected_out' exit=$expected_exit"
    FAIL=$((FAIL + 1))
  fi
}

run_test "feat/42-new-rule emits 42" "feat/42-new-rule" "42" 0
run_test "fix/123-analyzer-fp emits 123" "fix/123-analyzer-fp" "123" 0
run_test "chore/789-rename-skill emits 789" "chore/789-rename-skill" "789" 0
run_test "chore/routine-issue-555-tidy emits 555" "chore/routine-issue-555-tidy" "555" 0
run_test "feat/just-a-feature no number" "feat/just-a-feature" "" 1
run_test "worktree-foo-bar wrong prefix" "worktree-foo-bar" "" 1
run_test "cursor/abc-xyz cloud-agent no number" "cursor/abc-xyz" "" 1

# Configurable grammar: a consumer whose branches place the (numeric
# GitHub) issue number differently passes an ERE whose LAST capture group is
# that number. The downstream `Closes #N` needs a numeric GitHub issue id, so
# the capture must resolve to digits.
run_test "username-scoped scheme via custom pattern" "alice/1234-fix" "1234" 0 '^[^/]+/([0-9]+)-'
run_test "trailing-number scheme via custom pattern" "feat/add-widget-1234" "1234" 0 '-([0-9]+)$'
run_test "custom pattern, no match -> exit 1" "main" "" 1 '^[^/]+/([0-9]+)-'
# shellcheck disable=SC2016  # the placeholder is a literal test input, not an expansion
run_test "unsubstituted user_config placeholder falls back to default" "feat/42-x" "42" 0 '${user_config.branch_issue_pattern}'

# Layered `.claude/source-control.md` cascade. Each case gets its own fixture
# HOME and repo root. `layer <file> <value>` writes one `## branch_issue_pattern`
# section; the value is wrapped in backticks, as setup writes it.
layer() {
  mkdir -p "$(dirname "$1")"
  # shellcheck disable=SC2016  # the backticks are literal Markdown, not a command substitution
  printf '# Source control\n\n## subject_pattern\n\nConventional Commits\n\n## branch_issue_pattern\n\n`%s`\n\n## trailer_policy\n\nnone\n' "$2" >"$1"
}

new_case() {
  CASE_HOME="$(mktemp -d "${FIXTURES}/home.XXXXXX")"
  CASE_REPO="$(mktemp -d "${FIXTURES}/repo.XXXXXX")"
}

# `layer_raw <file> <content>` writes the file verbatim, for fence cases.
layer_raw() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "$2" >"$1"
}

# run_cfg <desc> <branch> <pattern-arg> <env-value|-> <want-out> <want-exit> <stderr-check> [<stderr-absent>]
# <stderr-check>: `empty` requires no stderr; otherwise an ERE stderr must match.
# <stderr-absent>: an optional fixed string stderr must NOT contain.
# stdout must equal <want-out> exactly, so a note never leaks onto it.
run_cfg() {
  local desc="$1" branch="$2" pattern="$3" envval="$4" want_out="$5" want_exit="$6" err_check="$7" err_absent="${8:-}"
  local out err rc errfile="${FIXTURES}/stderr"
  if [[ "$envval" == "-" ]]; then
    out=$(HOME="$CASE_HOME" CLAUDE_PROJECT_DIR="$CASE_REPO" bash "$PARSER" "$branch" "$pattern" 2>"$errfile")
  else
    out=$(HOME="$CASE_HOME" CLAUDE_PROJECT_DIR="$CASE_REPO" CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN="$envval" \
      bash "$PARSER" "$branch" "$pattern" 2>"$errfile")
  fi
  rc=$?
  err=$(<"$errfile")
  local err_ok=1
  if [[ "$err_check" == "empty" ]]; then
    [[ -z "$err" ]] || err_ok=0
  else
    printf '%s' "$err" | grep -Eq -- "$err_check" || err_ok=0
  fi
  [[ -z "$err_absent" || "$err" != *"$err_absent"* ]] || err_ok=0
  if [[ "$out" == "$want_out" && "$rc" -eq "$want_exit" && "$err_ok" -eq 1 ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       got     out='$out' exit=$rc stderr='$err'"
    echo "       wanted  out='$want_out' exit=$want_exit stderr~'$err_check'"
    FAIL=$((FAIL + 1))
  fi
}

DEPRECATION='deprecated.*branch_issue_pattern.*\.claude/source-control\.md'

new_case
layer "${CASE_REPO}/.claude/source-control.md" '^[^/]+/([0-9]+)-'
run_cfg "cascade only: team layer resolves" "alice.b/1234-fix" "" - "1234" 0 empty

new_case
run_cfg "userConfig positional only: resolves with a deprecation note" \
  "alice.b/1234-fix" '^[^/]+/([0-9]+)-' - "1234" 0 "$DEPRECATION"

new_case
run_cfg "userConfig env var only: resolves with a deprecation note" \
  "alice.b/1234-fix" "" '^[^/]+/([0-9]+)-' "1234" 0 "$DEPRECATION"

new_case
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_cfg "cascade beats a userConfig positional, no deprecation note" \
  "feat/12-add-widget-1234" '^[a-z]+/([0-9]+)-' - "1234" 0 empty

new_case
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_cfg "cascade beats the userConfig env var, no deprecation note" \
  "feat/12-add-widget-1234" "" '^[a-z]+/([0-9]+)-' "1234" 0 empty

new_case
layer "${CASE_HOME}/.claude/source-control.md" '^[^/]+/[^/]+/([0-9]+)-'
run_cfg "user-global layer alone resolves" "a/b/77-x" "" - "77" 0 empty

new_case
layer "${CASE_HOME}/.claude/source-control.md" '^[^/]+/[^/]+/([0-9]+)-'
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_cfg "team beats user-global" "a/5/77-x-9" "" - "9" 0 empty

new_case
layer "${CASE_HOME}/.claude/source-control.md" '^[^/]+/[^/]+/([0-9]+)-'
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.local.md" '^[a-z]+/([0-9]+)/'
run_cfg "local overlay beats team and user-global" "a/5/77-x-9" "" - "5" 0 empty

new_case
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.local.md" '(['
run_cfg "invalid local layer reported and skipped, team applies" \
  "feat/12-add-widget-1234" "" - "1234" 0 'source-control\.local\.md'

new_case
layer "${CASE_REPO}/.claude/source-control.md" '(['
run_cfg "invalid only layer skipped, falls through to userConfig with note" \
  "alice.b/1234-fix" '^[^/]+/([0-9]+)-' - "1234" 0 "$DEPRECATION"

new_case
layer "${CASE_REPO}/.claude/source-control.md" '(['
run_cfg "invalid only layer skipped, falls through to built-in default" \
  "feat/42-x" "" - "42" 0 'invalid'

new_case
# shellcheck disable=SC2016  # the placeholder is a literal test input, not an expansion
run_cfg "placeholder positional ignored, no config: default, no note" \
  "feat/42-x" '${user_config.branch_issue_pattern}' - "42" 0 empty

new_case
run_cfg "no config anywhere: built-in default, no note" "feat/42-x" "" - "42" 0 empty

new_case
run_cfg "no config anywhere, no match: exit 1, no note" "main" "" - "" 1 empty

# Fenced values: the first non-blank line inside a code fence is the value.
new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n```\n-([0-9]+)$\n```\n'
run_cfg "fenced value resolves" "feat/12-add-widget-1234" "" - "1234" 0 empty

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n~~~regex\n\n-([0-9]+)$\n~~~\n'
run_cfg "fenced value with an info string resolves" "feat/12-add-widget-1234" "" - "1234" 0 empty

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n```\n\n```\n'
run_cfg "empty fence reported with its path and skipped" \
  "feat/12-add-widget-1234" "" - "1234" 0 'repo\.[^ ]*/\.claude/source-control\.md.*empty'

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n```\n'
run_cfg "unterminated fence reported with its path and skipped" \
  "feat/12-add-widget-1234" "" - "1234" 0 'repo\.[^ ]*/\.claude/source-control\.md.*unterminated'

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" \
  $'## notes\n\n```md\n## branch_issue_pattern\n\n`^[a-z]+/([0-9]+)-`\n```\n\n## branch_issue_pattern\n\n`-([0-9]+)$`\n'
run_cfg "heading inside an earlier fence is ignored" "feat/12-add-widget-1234" "" - "1234" 0 empty

# The output must be a numeric issue id.
new_case
layer "${CASE_REPO}/.claude/source-control.md" '[0-9]+$'
run_cfg "pattern with no capture group: no output, note names the layer" \
  "feat/x-1234" "" - "" 1 'source-control\.md.*no capture group' '[0-9]+$'

new_case
layer "${CASE_REPO}/.claude/source-control.md" '^([a-z]+)/'
run_cfg "non-numeric capture: no output, note names the layer" \
  "feat/12-x" "" - "" 1 'source-control\.md.*non-numeric' '^([a-z]+)/'

new_case
run_cfg "non-numeric userConfig capture: no output, note names userConfig" \
  "feat/12-x" '^([a-z]+)/' - "" 1 'userConfig.*non-numeric'

# Backreferences are rejected.
new_case
layer "${CASE_REPO}/.claude/source-control.md" '^([a-z]+)/\1([0-9]+)'
run_cfg "backreference layer rejected, default applies" \
  "feat/42-x" "" - "42" 0 'source-control\.md.*backreference' '\1'

new_case
run_cfg "backreference userConfig ignored, default applies" \
  "feat/42-x" '^([a-z]+)/\1([0-9]+)' - "42" 0 'userConfig.*backreference'

# Notes never echo the raw repo-file value.
new_case
layer "${CASE_REPO}/.claude/source-control.md" 'ZQXMARK(['
run_cfg "invalid-ERE note omits the raw pattern" \
  "feat/42-x" "" - "42" 0 'source-control\.md' 'ZQXMARK'

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]

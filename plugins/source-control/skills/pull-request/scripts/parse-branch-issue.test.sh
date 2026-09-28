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

# A layer whose section exists but yields no usable pattern stops resolution:
# no stdout, exit 1, and a note naming the layer and `stopped`, even when a
# lower layer, the userConfig, or the default would match.
STOPPED='resolution stopped, no issue id emitted'

new_case
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.local.md" '(['
run_cfg "invalid local layer stops resolution, team never applies" \
  "feat/12-add-widget-1234" "" - "" 1 "source-control\.local\.md.*invalid ERE.*${STOPPED}"

new_case
layer "${CASE_REPO}/.claude/source-control.local.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.md" '(['
run_cfg "valid local layer wins before an invalid team layer is read" \
  "feat/12-add-widget-1234" "" - "1234" 0 empty

new_case
layer "${CASE_REPO}/.claude/source-control.md" '(['
run_cfg "invalid only layer stops resolution, never reaches the userConfig" \
  "alice.b/1234-fix" '^[^/]+/([0-9]+)-' - "" 1 "invalid ERE.*${STOPPED}" 'deprecated'

new_case
layer "${CASE_REPO}/.claude/source-control.md" '(['
run_cfg "invalid only layer stops resolution, never reaches the userConfig env var" \
  "alice.b/1234-fix" "" '^[^/]+/([0-9]+)-' "" 1 "invalid ERE.*${STOPPED}" 'deprecated'

new_case
layer "${CASE_REPO}/.claude/source-control.md" '(['
run_cfg "invalid only layer stops resolution, never reaches the built-in default" \
  "feat/42-x" "" - "" 1 "invalid ERE.*${STOPPED}"

new_case
layer "${CASE_HOME}/.claude/source-control.md" '(['
run_cfg "invalid user-global layer stops resolution, never reaches the default" \
  "feat/42-x" "" - "" 1 "home\.[^ ]*/\.claude/source-control\.md.*${STOPPED}"

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
run_cfg "empty fence stops resolution, note names its path" \
  "feat/12-add-widget-1234" "" - "" 1 "repo\.[^ ]*/\.claude/source-control\.md.*empty.*${STOPPED}"

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n```\n'
run_cfg "unterminated fence stops resolution, note names its path" \
  "feat/12-add-widget-1234" "" - "" 1 "repo\.[^ ]*/\.claude/source-control\.md.*unterminated.*${STOPPED}"

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
run_cfg "backreference layer stops resolution, never the default" \
  "feat/42-x" "" - "" 1 "source-control\.md.*backreference.*${STOPPED}" '\1'

new_case
run_cfg "backreference userConfig ignored, default applies" \
  "feat/42-x" '^([a-z]+)/\1([0-9]+)' - "42" 0 'userConfig.*backreference.*ignored'

new_case
run_cfg "invalid-ERE userConfig env var ignored, default applies" \
  "feat/42-x" "" '([' "42" 0 'userConfig.*invalid ERE.*ignored' 'stopped'

# Notes never echo the raw repo-file value.
new_case
layer "${CASE_REPO}/.claude/source-control.md" 'ZQXMARK(['
run_cfg "invalid-ERE note omits the raw pattern" \
  "feat/42-x" "" - "" 1 'source-control\.md.*stopped' 'ZQXMARK'

# Section parsing. The branch `feat/12-widget-34` makes a wrong source visible:
# the intended trailing-number pattern gives 34, the built-in default gives 12.
WN="feat/12-widget-34"

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'\xef\xbb\xbf## branch_issue_pattern\n\n`-([0-9]+)$`\n'
run_cfg "UTF-8 BOM before the heading resolves" "$WN" "" - "34" 0 empty

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern ##  \n\n`-([0-9]+)$`\n'
run_cfg "closing hash sequence on the heading resolves" "$WN" "" - "34" 0 empty

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern:\n\n`-([0-9]+)$`\n'
run_cfg "near-miss heading stops resolution: no output, never the default" \
  "$WN" "" - "" 1 'source-control\.md.*near-miss heading'

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## Branch_Issue_Pattern\n\n`-([0-9]+)$`\n'
run_cfg "near-miss heading in other case stops resolution" "$WN" "" - "" 1 'near-miss heading'

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern (ERE)\n\n`^feat/([0-9]+)-`\n'
run_cfg "near-miss team layer stops resolution over a valid user-global layer" \
  "$WN" "" - "" 1 'source-control\.md.*near-miss heading'

new_case
layer "${CASE_REPO}/.claude/source-control.local.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern:\n\n`^feat/([0-9]+)-`\n'
run_cfg "valid local layer wins before a near-miss team layer is read" "$WN" "" - "34" 0 empty

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## notes\n\n```\n## branch_issue_pattern:\n```\n\n## branch_issue_pattern\n\n`-([0-9]+)$`\n'
run_cfg "near-miss heading inside a fence is ignored" "$WN" "" - "34" 0 empty

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n### note\n`^feat/([0-9]+)-`\n'
run_cfg "heading as the first value line stops resolution over a valid user-global layer" \
  "$WN" "" - "" 1 "source-control\.md.*heading.*${STOPPED}"

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n<!-- first number -->\n`^feat/([0-9]+)-`\n'
run_cfg "HTML comment as the first value line stops resolution over a valid user-global layer" \
  "$WN" "" - "" 1 "source-control\.md.*comment.*${STOPPED}"

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n<!-- first number -->\n'
run_cfg "HTML comment first line alone: no output, never the default 12" \
  "$WN" "" - "" 1 "source-control\.md.*comment.*${STOPPED}"

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n```\n^feat/([0-9]+)-\n'
run_cfg "unterminated fence with content stops resolution" \
  "$WN" "" - "" 1 "source-control\.md.*unterminated.*${STOPPED}"

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n## trailer_policy\n\nnone\n'
run_cfg "section with no value before the next heading stops resolution" \
  "$WN" "" - "" 1 "source-control\.md.*no value.*${STOPPED}"

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n'
run_cfg "section with no value at end of file stops resolution, never the default" \
  "$WN" "" - "" 1 "source-control\.md.*no value.*${STOPPED}"

new_case
layer_raw "${CASE_REPO}/.claude/source-control.md" $'## branch_issue_pattern\n\n``\n'
run_cfg "value of only backticks stops resolution, never the default" \
  "$WN" "" - "" 1 "source-control\.md.*no value.*${STOPPED}"

# Pattern limits, checked before the pattern is compiled or matched. Each
# rejected layer stops resolution; the user-global `-([0-9]+)$` (34) and the
# default (12) must both stay unreached.
new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.md" "^feat/([0-9]+)-|$(printf 'z%.0s' {1..190})"
run_cfg "pattern over 200 characters stops resolution" \
  "$WN" "" - "" 1 "source-control\.md.*too long.*${STOPPED}" 'zzzzzzzz'

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.md" '^feat/x{0,17}([0-9]+)-'
run_cfg "repetition bound over 16 stops resolution" \
  "$WN" "" - "" 1 "source-control\.md.*repetition bound.*${STOPPED}" 'x{0,17}'

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.md" '^feat/((1+)+)[0-9]*-'
run_cfg "quantifier on a group holding a quantifier stops resolution" \
  "$WN" "" - "" 1 "source-control\.md.*nested quantifier.*${STOPPED}" '(1+)+'

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.md" '^[a-z]+/((x{0,255}){0,255})([0-9]+)-'
run_cfg "large nested bounded repetition stops resolution before it is compiled" \
  "$WN" "" - "" 1 "source-control\.md.*repetition bound.*${STOPPED}" 'x{0,255}'

new_case
layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
layer "${CASE_REPO}/.claude/source-control.md" '^feat/([0-9]+)-\1'
run_cfg "backreference team layer stops resolution over a valid user-global layer" \
  "$WN" "" - "" 1 "source-control\.md.*backreference.*${STOPPED}" '\1'

new_case
run_cfg "nested-quantifier userConfig ignored, default applies" \
  "$WN" '^feat/((1+)+)[0-9]*-' - "12" 0 'userConfig.*nested quantifier'

new_case
layer "${CASE_REPO}/.claude/source-control.md" '^[^/]+/([0-9]+)-'
run_cfg "documented username-scoped example allowed" "alice/1234-fix" "" - "1234" 0 empty

new_case
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_cfg "documented trailing-number example allowed" "$WN" "" - "34" 0 empty

new_case
layer "${CASE_REPO}/.claude/source-control.md" '^[a-z]+/(routine-issue-)?([0-9]+)-'
run_cfg "built-in default as a layer value allowed" "chore/routine-issue-555-tidy" "" - "555" 0 empty

new_case
layer "${CASE_REPO}/.claude/source-control.md" '^[a-z]+/([{]x{2}|[0-9]{1,16})-'
run_cfg "bounds up to 16 and a literal brace in brackets allowed" "feat/42-x" "" - "42" 0 empty

# Home-rooted session: team and overlay collapse onto ~/.claude and must not
# be read as team. Overlay at home is skipped; user-global is the only layer.
HOME_NOTE='team and overlay not applicable: project root is the home directory'

new_case
layer "${CASE_HOME}/.claude/source-control.md" '^[^/]+/[^/]+/([0-9]+)-'
layer "${CASE_HOME}/.claude/source-control.local.md" '^[a-z]+/([0-9]+)/'
CASE_REPO="$CASE_HOME"
run_cfg "home project root reads user-global once, never overlay as team" \
  "a/5/77-x-9" "" - "77" 0 "$HOME_NOTE"

new_case
layer "${CASE_HOME}/.claude/source-control.md" '^[^/]+/[^/]+/([0-9]+)-'
layer "${CASE_HOME}/.claude/source-control.local.md" '^[a-z]+/([0-9]+)/'
CASE_REPO="$(dirname "$CASE_HOME")"
run_cfg "an ancestor of home also skips team and overlay" \
  "a/5/77-x-9" "" - "77" 0 "$HOME_NOTE"

new_case
layer "${CASE_HOME}/.claude/source-control.md" '^[^/]+/([0-9]+)-'
layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_cfg "a repo root that is not home still lets team beat user-global" \
  "a/5/77-x-9" "" - "9" 0 empty

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]

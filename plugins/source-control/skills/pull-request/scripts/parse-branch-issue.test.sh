#!/usr/bin/env bash

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="${SCRIPT_DIR}/parse-branch-issue.sh"

if [[ ! -x "$PARSER" ]]; then
  echo "FAIL: parser missing or not executable: $PARSER" >&2
  exit 1
fi

PASS=0
FAIL=0

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
run_test "dossier/42-auth-notes emits 42" "dossier/42-auth-notes" "42" 0
run_test "feat/just-a-feature no number" "feat/just-a-feature" "" 1
run_test "worktree-foo-bar wrong prefix" "worktree-foo-bar" "" 1
run_test "cursor/abc-xyz cloud-agent no number" "cursor/abc-xyz" "" 1

run_test "username-scoped scheme via custom pattern" "alice/1234-fix" "1234" 0 '^[^/]+/([0-9]+)-'
run_test "trailing-number scheme via custom pattern" "feat/add-widget-1234" "1234" 0 '-([0-9]+)$'
run_test "custom pattern, no match -> exit 1" "main" "" 1 '^[^/]+/([0-9]+)-'
# shellcheck disable=SC2016  # the placeholder is a literal test input, not an expansion
run_test "unsubstituted user_config placeholder falls back to default" "feat/42-x" "42" 0 '${user_config.branch_issue_pattern}'
run_test "tracker key via custom pattern" "feat/SW2-1234-x" "SW2-1234" 0 '^[^/]+/([A-Z][A-Z0-9]*-[0-9]+)-'

run_no_default() {
  local desc="$1" pattern="$2" expected_out="$3" expected_exit="$4" actual_out actual_exit
  actual_out=$(bash "$PARSER" "feat/42-x" "$pattern" --no-default 2>/dev/null)
  actual_exit=$?
  if [[ "$actual_out" == "$expected_out" && "$actual_exit" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (got out='$actual_out' exit=$actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}
run_no_default "--no-default with no consumer pattern exits 3, prints nothing" "" "" 3
run_no_default "--no-default still applies a consumer pattern" '^[^/]+/([0-9]+)-' "42" 0

retired_md_layer() {
  mkdir -p "$(dirname "$1")"
  # shellcheck disable=SC2016  # the backticks are literal Markdown, not a command substitution
  printf '# Source control\n\n## subject_pattern\n\nConventional Commits\n\n## branch_issue_pattern\n\n`%s`\n\n## trailer_policy\n\nnone\n' "$2" >"$1"
  track "$1"
}

yaml_layer() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' 'pr_open_state: ready' "branch_issue_pattern: '$2'" >"$1"
  track "$1"
}

write_personal_yaml() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "branch_issue_pattern: '$2'" >"$1"
}

TEAM_YAML_REL="docs/conventions/source-control.yaml"
PERSONAL_YAML_REL="docs/conventions/source-control.local.yaml"

track() {
  git -C "$CASE_REPO" add -f -- "$1" >/dev/null 2>&1 || true
}

new_case() {
  CASE_HOME="$(mktemp -d "${FIXTURES}/home.XXXXXX")"
  CASE_REPO="$(mktemp -d "${FIXTURES}/repo.XXXXXX")"
  git init -q "$CASE_REPO"
}

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
    grep -Eq -- "$err_check" <<<"$err" || err_ok=0
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

DEPRECATION='deprecated.*branch_issue_pattern.*docs/conventions/source-control\.yaml'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '^[^/]+/([0-9]+)-'
run_cfg "cascade only: team layer resolves" "alice.b/1234-fix" "" - "1234" 0 empty

new_case
run_cfg "userConfig positional only: resolves with a deprecation note" \
  "alice.b/1234-fix" '^[^/]+/([0-9]+)-' - "1234" 0 "$DEPRECATION"

new_case
run_cfg "userConfig env var only: resolves with a deprecation note" \
  "alice.b/1234-fix" "" '^[^/]+/([0-9]+)-' "1234" 0 "$DEPRECATION"

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '-([0-9]+)$'
run_cfg "cascade beats a userConfig positional, no deprecation note" \
  "feat/12-add-widget-1234" '^[a-z]+/([0-9]+)-' - "1234" 0 empty

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '-([0-9]+)$'
run_cfg "cascade beats the userConfig env var, no deprecation note" \
  "feat/12-add-widget-1234" "" '^[a-z]+/([0-9]+)-' "1234" 0 empty

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^[a-z]+/([0-9]+)/'
run_cfg "personal override beats team" "a/5/77-x-9" "" - "5" 0 empty

STOPPED='resolution stopped, no issue id emitted'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '(['
run_cfg "invalid local layer stops resolution, team never applies" \
  "feat/12-add-widget-1234" "" - "" 1 "source-control\.local\.yaml.*invalid ERE.*${STOPPED}"

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '-([0-9]+)$'
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '(['
run_cfg "valid local layer wins before an invalid team layer is read" \
  "feat/12-add-widget-1234" "" - "1234" 0 empty

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '(['
run_cfg "invalid only layer stops resolution, never reaches the userConfig" \
  "alice.b/1234-fix" '^[^/]+/([0-9]+)-' - "" 1 "invalid ERE.*${STOPPED}" 'deprecated'

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '(['
run_cfg "invalid only layer stops resolution, never reaches the userConfig env var" \
  "alice.b/1234-fix" "" '^[^/]+/([0-9]+)-' "" 1 "invalid ERE.*${STOPPED}" 'deprecated'

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '(['
run_cfg "invalid only layer stops resolution, never reaches the built-in default" \
  "feat/42-x" "" - "" 1 "invalid ERE.*${STOPPED}"

new_case
# shellcheck disable=SC2016  # the placeholder is a literal test input, not an expansion
run_cfg "placeholder positional ignored, no config: default, no note" \
  "feat/42-x" '${user_config.branch_issue_pattern}' - "42" 0 empty

new_case
run_cfg "no config anywhere: built-in default, no note" "feat/42-x" "" - "42" 0 empty

new_case
run_cfg "no config anywhere, no match: exit 1, no note" "main" "" - "" 1 empty

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '[0-9]+$'
run_cfg "pattern with no capture group: no output, note names the layer" \
  "feat/x-1234" "" - "" 1 'source-control\.local\.yaml.*no capture group' '[0-9]+$'

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^([a-z]+)/'
run_cfg "non-numeric capture: no output, note names the layer" \
  "feat/12-x" "" - "" 1 'source-control\.local\.yaml.*non-numeric' '^([a-z]+)/'

new_case
run_cfg "non-numeric userConfig capture: no output, note names userConfig" \
  "feat/12-x" '^([a-z]+)/' - "" 1 'userConfig.*non-numeric'

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^([a-z]+)/\1([0-9]+)'
run_cfg "backreference layer stops resolution, never the default" \
  "feat/42-x" "" - "" 1 "source-control\.local\.yaml.*backreference.*${STOPPED}" '\1'

new_case
run_cfg "backreference userConfig ignored, default applies" \
  "feat/42-x" '^([a-z]+)/\1([0-9]+)' - "42" 0 'userConfig.*backreference.*ignored'

new_case
run_cfg "invalid-ERE userConfig env var ignored, default applies" \
  "feat/42-x" "" '([' "42" 0 'userConfig.*invalid ERE.*ignored' 'stopped'

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" 'ZQXMARK(['
run_cfg "invalid-ERE note omits the raw pattern" \
  "feat/42-x" "" - "" 1 'source-control\.local\.yaml.*stopped' 'ZQXMARK'

WN="feat/12-widget-34"

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" "^feat/([0-9]+)-|$(printf 'z%.0s' {1..190})"
run_cfg "pattern over 200 characters stops resolution" \
  "$WN" "" - "" 1 "source-control\.local\.yaml.*too long.*${STOPPED}" 'zzzzzzzz'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^feat/x{0,17}([0-9]+)-'
run_cfg "repetition bound over 16 stops resolution" \
  "$WN" "" - "" 1 "source-control\.local\.yaml.*repetition bound.*${STOPPED}" 'x{0,17}'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^feat/((1+)+)[0-9]*-'
run_cfg "quantifier on a group holding a quantifier stops resolution" \
  "$WN" "" - "" 1 "source-control\.local\.yaml.*nested quantifier.*${STOPPED}" '(1+)+'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^[a-z]+/((x{0,255}){0,255})([0-9]+)-'
run_cfg "large nested bounded repetition stops resolution before it is compiled" \
  "$WN" "" - "" 1 "source-control\.local\.yaml.*repetition bound.*${STOPPED}" 'x{0,255}'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^feat/([0-9]+)-\1'
run_cfg "backreference local layer stops resolution over a valid team layer" \
  "$WN" "" - "" 1 "source-control\.local\.yaml.*backreference.*${STOPPED}" '\1'

new_case
run_cfg "nested-quantifier userConfig ignored, default applies" \
  "$WN" '^feat/((1+)+)[0-9]*-' - "12" 0 'userConfig.*nested quantifier'

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^[^/]+/([0-9]+)-'
run_cfg "documented username-scoped example allowed" "alice/1234-fix" "" - "1234" 0 empty

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '-([0-9]+)$'
run_cfg "documented trailing-number example allowed" "$WN" "" - "34" 0 empty

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^[a-z]+/(routine-issue-)?([0-9]+)-'
run_cfg "built-in default as a layer value allowed" "chore/routine-issue-555-tidy" "" - "555" 0 empty

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^[a-z]+/([{]x{2}|[0-9]{1,16})-'
run_cfg "bounds up to 16 and a literal brace in brackets allowed" "feat/42-x" "" - "42" 0 empty

HOME_NOTE='team and personal override not applicable: project root is the home directory'

new_case
git init -q "$CASE_HOME"
CASE_REPO="$CASE_HOME"
yaml_layer "${CASE_HOME}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_HOME}/$PERSONAL_YAML_REL" '-([0-9]+)$'
run_cfg "home project root skips team and personal override" \
  "$WN" "" - "12" 0 "$HOME_NOTE"

new_case
CASE_REPO="$(mktemp -d "${FIXTURES}/anc.XXXXXX")"
CASE_HOME="${CASE_REPO}/home"
mkdir -p "$CASE_HOME"
git init -q "$CASE_REPO"
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '-([0-9]+)$'
run_cfg "an ancestor of home also skips team and personal override" \
  "$WN" "" - "12" 0 "$HOME_NOTE"

new_case
CASE_REPO="$(mktemp -d "${FIXTURES}/norepo.XXXXXX")"
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '-([0-9]+)$'
run_cfg "a root outside any git repository skips team and personal override" \
  "$WN" "" - "12" 0 "project root is not inside a git repository"

mklink() {
  MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null && [[ -L "$2" ]] && return 0
  echo "SKIP: host cannot create symlinks: $3" >&2
  return 1
}

new_case
write_personal_yaml "${CASE_HOME}/$PERSONAL_YAML_REL" '-([0-9]+)$'
CASE_REPO="${FIXTURES}/home-alias.$$"
if mklink "$CASE_HOME" "$CASE_REPO" "a symlink alias of home skips team and personal override"; then
  run_cfg "a symlink alias of home also skips team and personal override" \
    "$WN" "" - "12" 0 "$HOME_NOTE"
fi

run_explain() {
  local desc="$1" branch="$2" want_out="$3" want_layer="$4" out err
  out=$(HOME="$CASE_HOME" CLAUDE_PROJECT_DIR="$CASE_REPO" bash "$PARSER" "$branch" "" --explain 2>"${FIXTURES}/stderr")
  err=$(<"${FIXTURES}/stderr")
  if [[ "$out" == "$want_out" ]] && grep -Eq -- "branch_issue_pattern layer: ${want_layer}" <<<"$err"; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       got     out='$out' stderr='$err'"
    echo "       wanted  out='$want_out' stderr~'${want_layer}'"
    FAIL=$((FAIL + 1))
  fi
}

new_case
yaml_layer "${CASE_REPO}/docs/conventions/source-control.yaml" '^[^/]+/([0-9]+)-'
run_cfg "yaml team layer resolves with no note" "alice.b/1234-fix" "" - "1234" 0 empty
run_explain "the resolver names the YAML as the supplying layer" "alice.b/1234-fix" "1234" \
  'docs/conventions/source-control\.yaml$'

new_case
yaml_layer "${CASE_REPO}/docs/conventions/source-control.yaml" '-([0-9]+)$'
retired_md_layer "${CASE_REPO}/.claude/source-control.md" '^[^/]+/([0-9]+)-'
run_cfg "the YAML value applies beside a retired markdown file" "feat/12-add-widget-1234" "" - "1234" 0 empty
run_explain "the layer is the YAML when the retired file also carries the key" "feat/12-add-widget-1234" "1234" \
  'docs/conventions/source-control\.yaml$'

new_case
mkdir -p "${CASE_REPO}/docs/conventions"
printf '%s\n' 'pr_open_state: ready' >"${CASE_REPO}/docs/conventions/source-control.yaml"
track "${CASE_REPO}/docs/conventions/source-control.yaml"
retired_md_layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_cfg "the retired markdown is not read when the YAML lacks the key" "feat/12-add-widget-1234" "" - "12" 0 empty
run_explain "the default supplies the pattern when the YAML lacks the key" "feat/12-add-widget-1234" "12" 'default$'

new_case
retired_md_layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_explain "no YAML file: the retired team markdown is not read, the default applies" "feat/12-add-widget-1234" "12" \
  'default$'

new_case
yaml_layer "${CASE_REPO}/docs/conventions/source-control.yaml" '(['
run_cfg "an invalid YAML pattern stops resolution" "alice.b/1234-fix" "" - "" 1 "invalid ERE.*${STOPPED}"

new_case
yaml_layer "${CASE_REPO}/docs/conventions/source-control.yaml" '^[^/]+/([0-9]+)-'
printf '%s\n' 'branch_issue_pattern: a' >>"${CASE_REPO}/docs/conventions/source-control.yaml"
retired_md_layer "${CASE_REPO}/.claude/source-control.md" '^[^/]+/([0-9]+)-'
run_cfg "a YAML the shared reader rejects stops resolution" \
  "alice.b/1234-fix" "" - "" 1 "could not be parsed.*${STOPPED}"

new_case
yaml_layer "${CASE_REPO}/docs/conventions/source-control.yaml" '^[^/]+/([0-9]+)-'
run_cfg "the YAML beats a userConfig positional, no deprecation note" \
  "alice.b/1234-fix" '^[a-z]+/([0-9]+)-' - "1234" 0 empty

new_case
yaml_layer "${CASE_REPO}/docs/conventions/source-control.yaml" '-([0-9]+)$'
git -C "$CASE_REPO" rm -q --cached -- docs/conventions/source-control.yaml
retired_md_layer "${CASE_REPO}/.claude/source-control.md" '-([0-9]+)$'
run_cfg "an untracked team YAML is ignored, and a tracked retired file is not read" \
  "feat/12-add-widget-1234" "" - "12" 0 "source-control\.yaml is not tracked by git"

new_case
run_explain "the default is the named layer when nothing is configured" "feat/42-x" "42" 'default$'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^[^/]+/([0-9]+)-'
run_cfg "new layers only: the personal YAML beats the team YAML" \
  "feat/12-add-widget-1234" "" - "12" 0 empty
run_explain "the personal YAML is the named layer" "feat/12-add-widget-1234" "12" \
  'docs/conventions/source-control\.local\.yaml$'

new_case
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
mkdir -p "${CASE_REPO}/docs/conventions"
printf '%s\n' 'trailer_policy: none' >"${CASE_REPO}/$PERSONAL_YAML_REL"
run_cfg "a personal YAML without the key falls through to the team YAML" \
  "feat/12-add-widget-1234" "" - "1234" 0 empty

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '(['
run_cfg "an invalid personal YAML pattern stops resolution" \
  "feat/12-add-widget-1234" "" - "" 1 "invalid ERE.*${STOPPED}"

new_case
write_personal_yaml "${CASE_REPO}/$PERSONAL_YAML_REL" '^[^/]+/([0-9]+)-'
printf '%s\n' 'branch_issue_pattern: a' >>"${CASE_REPO}/$PERSONAL_YAML_REL"
run_cfg "a personal YAML the shared reader rejects stops resolution" \
  "feat/12-add-widget-1234" "" - "" 1 "source-control\.local\.yaml could not be parsed.*${STOPPED}"

new_case
retired_md_layer "${CASE_HOME}/.claude/source-control.md" '-([0-9]+)$'
retired_md_layer "${CASE_REPO}/.claude/source-control.local.md" '-([0-9]+)$'
run_cfg "retired ~/.claude/source-control.md and .claude/source-control.local.md are ignored cleanly" \
  "feat/12-add-widget-1234" "" - "12" 0 empty
run_explain "default supplies the pattern when only retired .claude files exist" \
  "feat/12-add-widget-1234" "12" 'default$'

new_case
retired_md_layer "${CASE_HOME}/.claude/source-control.md" '(['
retired_md_layer "${CASE_REPO}/.claude/source-control.local.md" '(['
yaml_layer "${CASE_REPO}/$TEAM_YAML_REL" '-([0-9]+)$'
run_cfg "retired .claude files (even malformed) are ignored beside the team YAML" \
  "feat/12-add-widget-1234" "" - "1234" 0 empty

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]

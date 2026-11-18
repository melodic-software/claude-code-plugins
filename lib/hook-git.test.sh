#!/usr/bin/env bash
# test-scope: lib/hook-utils.sh lib/resolve-convention-pattern.sh
# test-scope: plugins/eol-normalizer/hooks/normalize-eol.sh plugins/source-control/hooks/worktree-remove-gate.sh
# test-scope: lib/git-hooks/resolve-tool.sh plugins/source-control/scripts/reap-project-plugin-records.sh
# test-scope: plugins/bash-format/git-hooks/adapters.sh plugins/javascript-format/git-hooks/adapters.sh
# test-scope: plugins/markdown-format/git-hooks/adapters.sh plugins/markdown-format/git-hooks/markdown-gates.sh
# test-scope: plugins/python-format/git-hooks/adapters.sh
# test-scope: plugins/actionlint/hooks/actionlint-check.sh plugins/bash-format/hooks/bash-format.sh
# test-scope: plugins/go-format/hooks/go-format.sh plugins/javascript-format/hooks/javascript-format.sh
# test-scope: plugins/markdown-format/hooks/markdown-format.sh plugins/powershell-format/hooks/powershell-format.sh
# test-scope: plugins/python-format/hooks/python-format.sh plugins/spelling/hooks/spelling.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_CONFIG CLAUDE_PROJECT_DIR

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$LIB/../plugins"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
T="$(cd -P "$T" && pwd)"

FAILED=0
PASSED=0
pass() {
  PASSED=$((PASSED + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}
expect() {
  local label="$1"
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

command -v git >/dev/null 2>&1 || {
  echo "SKIP: git not on PATH"
  exit 0
}

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOOK_TELEMETRY_SINK=
g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

R="$T/repo"
mkdir -p "$R/docs/conventions" "$R/.work"
printf '.work/\nignored.txt\n' >"$R/.gitignore"
printf 'a\n' >"$R/a.txt"
printf 'subject_pattern: "^feat"\n' >"$R/docs/conventions/source-control.yaml"
g init -q "$R"
g -C "$R" add .
g -C "$R" commit -q -m init
g -C "$R" worktree add -q -b wt "$T/wt"
printf 'x\n' >"$T/wt/untracked.txt"

MARK="$T/fsmonitor-ran"
printf '#!/bin/sh\ntouch "%s"\n' "$MARK" >"$T/fsmonitor.sh"
chmod +x "$T/fsmonitor.sh"
g -C "$R" config core.fsmonitor "$T/fsmonitor.sh"

git -C "$R" check-ignore -q -- a.txt >/dev/null 2>&1
if [[ -e "$MARK" ]]; then
  pass "fixture: a plain git check-ignore runs the planted fsmonitor"
else
  fail "fixture: the planted fsmonitor never fires, so no case below proves anything"
fi

not_run() {
  if [[ -e "$MARK" ]]; then fail "$1: ran the repository's core.fsmonitor"; else pass "$1: core.fsmonitor never runs"; fi
  rm -f "$MARK"
}
rm -f "$MARK"

sh "$LIB/resolve-convention-pattern.sh" "$R" subject_pattern >/dev/null 2>&1
not_run "resolve-convention-pattern tracked-file check"

bash -c 'source "$1/hook-utils.sh" && source "$2" && normalize_eol_resolve_attrs "$3" a.txt' _ \
  "$PLUGINS/eol-normalizer/hooks" "$PLUGINS/eol-normalizer/hooks/normalize-eol.sh" "$R"
not_run "normalize-eol check-attr"

out=$(jq -n --arg p "$T/wt" '{worktree_path:$p,session_id:"s"}' |
  bash "$PLUGINS/source-control/hooks/worktree-remove-gate.sh" 2>&1)
rc=$?
not_run "worktree-remove-gate status"
refused=no
[[ "$out" == *"uncommitted or untracked"* ]] && refused=yes
expect "worktree-remove-gate: still refuses a worktree with an untracked file (rc $rc: $out)" test "$rc:$refused" = "1:yes"

mkdir -p "$R/node_modules/.bin" "$R/.venv/bin"
for bin in node_modules/.bin/biome node_modules/.bin/markdownlint-cli2 .venv/bin/ruff; do
  printf '#!/bin/sh\n' >"$R/$bin"
  chmod +x "$R/$bin"
done
adapter() {
  bash -c 'p="$1/$2" && shift 2 &&
    source "$p/hooks/hook-utils.sh" && source "$p/lib/git-hooks/resolve-tool.sh" &&
    { [[ ! -f "$p/git-hooks/markdown-gates.sh" ]] || source "$p/git-hooks/markdown-gates.sh"; } &&
    source "$p/git-hooks/adapters.sh" || exit 99
    declare -F "$1" >/dev/null || exit 99
    "$@"' _ "$PLUGINS" "$@" >/dev/null 2>&1
  [[ $? -ne 99 ]] || fail "$1: its hook-utils.sh, resolve-tool.sh or adapters did not load, or $2 is gone"
}
for plugin in bash-format javascript-format markdown-format python-format; do
  adapter "$plugin" rt_adapter_in_repo format "$R"
  not_run "$plugin adapter config lookup"
done
adapter bash-format rt_adapter_in_repo lint "$R"
not_run "bash-format adapter shellcheckrc lookup"
adapter javascript-format jf__local_bin_here "$R"
not_run "javascript-format committed node_modules check"
adapter python-format pf__venv_here "$R"
not_run "python-format committed .venv check"
adapter markdown-format md_local_bin "$R" "$R"
not_run "markdown-format committed node_modules check"

g -C "$R" worktree add -q -b wt2 "$T/wt2"
mkdir -p "$T/bin"
record="[{\"id\":\"p@m\",\"projectPath\":\"$T/wt2\",\"scope\":\"project\"}]"
# shellcheck disable=SC2016 # $2 is the stub's own argument
printf '#!/bin/sh\n[ "$2" = list ] && echo %s\nexit 0\n' "'$record'" >"$T/bin/claude"
chmod +x "$T/bin/claude"
rm -f "$MARK"
out=$(PATH="$T/bin:$PATH" bash "$PLUGINS/source-control/scripts/reap-project-plugin-records.sh" \
  --worktree-path "$T/wt2" 2>&1)
rc=$?
not_run "reap-project-plugin-records settings state"
expect "reap-project-plugin-records: reaches the survivor check past the settings state (rc $rc: $out)" test "$rc" = 1

E="$T/eot"
mkdir -p "$E/.github/workflows"
for f in a.sh a.go a.js a.md a.py a.ps1 a.txt .github/workflows/ci.yml; do printf 'x\n' >"$E/$f"; done
g init -q "$E"
g -C "$E" add .
g -C "$E" commit -q -m init
for f in a.sh a.go a.js a.md a.py a.ps1 a.txt .github/workflows/ci.yml; do printf 'y\n' >>"$E/$f"; done
g -C "$E" config core.fsmonitor "$T/fsmonitor.sh"
for tool in actionlint shfmt shellcheck gofmt biome markdownlint-cli2 ruff pwsh typos; do
  printf '#!/bin/sh\nexit 0\n' >"$T/bin/$tool"
  chmod +x "$T/bin/$tool"
done
mkdir -p "$T/gitbin"
# shellcheck disable=SC2016 # expanded by the shim when git runs
printf '#!/bin/sh\necho "$GIT_CONFIG_COUNT" >>"%s"\nexec "%s" "$@"\n' "$T/git-calls" "$(command -v git)" >"$T/gitbin/git"
chmod +x "$T/gitbin/git"
for hook in actionlint/hooks/actionlint-check.sh:lint bash-format/hooks/bash-format.sh:lint \
  go-format/hooks/go-format.sh:format javascript-format/hooks/javascript-format.sh:lint \
  markdown-format/hooks/markdown-format.sh:lint powershell-format/hooks/powershell-format.sh:lint \
  python-format/hooks/python-format.sh:lint spelling/hooks/spelling.sh:lint; do
  script="${hook%:*}" entry="${script%%/*}/git-hooks/${hook##*:}.sh"
  rm -f "$MARK"
  (cd "$E" && PATH="$T/bin:$PATH" bash "$PLUGINS/$entry" --worktree) </dev/null >/dev/null 2>&1
  if [[ -e "$MARK" ]]; then
    pass "fixture: $entry --worktree run on its own reads the index"
  else
    fail "fixture: $entry --worktree never runs the planted fsmonitor, so its hook case proves nothing"
  fi
  rm -f "$MARK" "$T/git-calls"
  (cd "$E" && printf '{}' | PATH="$T/gitbin:$T/bin:$PATH" bash "$PLUGINS/$script" --end-of-turn) >/dev/null 2>&1
  not_run "$script --end-of-turn"
  expect "$script --end-of-turn: its entry ran git with GIT_CONFIG_COUNT=2" grep -qx 2 "$T/git-calls"
done

rm -f "$T/git-calls"
(
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=kept
  # shellcheck source=hook-utils.sh
  source "$LIB/hook-utils.sh"
  hook::git_untrusted_env
  git -C "$E" config --get user.name >"$T/git-calls"
  git -C "$E" config --get core.hooksPath >>"$T/git-calls"
)
expect "hook::git_untrusted_env appends after a caller's own GIT_CONFIG_COUNT entries ($(tr '\n' ' ' <"$T/git-calls"))" \
  test "$(tr '\n' ' ' <"$T/git-calls")" = "kept /dev/null "

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
((FAILED == 0))

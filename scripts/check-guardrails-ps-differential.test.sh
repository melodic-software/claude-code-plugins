#!/usr/bin/env bash
# Tests for check-guardrails-ps-differential.sh. Each case builds a throwaway
# repository holding a copy of plugins/guardrails, commits it as the base, and
# plants one change in the working tree: a guard that allows what the base
# refuses must fail the check wherever it was planted (a consumer, the shared
# classifier library, the Bash row's argv, or a token-only path), and a
# branch-only refusal must not.
# shellcheck disable=SC2016  # planted source lines are literal shell
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""

# A literal git reset, one behind a `{` (special-construct), one through a
# launcher, a --no-verify commit, and two git-free controls.
CORPUS_LINES=(
  '"git reset --hard"'
  '"Write-Host {a}; git reset --hard"'
  '"pwsh -Command \"git reset --hard\""'
  '"git commit --no-verify -m x"'
  '"git status"'
  '"Write-Output ok"'
)

new_fixture() { # <out-var>
  fixture_tree::build "$1" --sut check-guardrails-ps-differential.sh --git --plugins --label ps-diff || return 1
  local root=${!1}
  cp -R "$REPO_ROOT/plugins/guardrails" "$root/plugins/" || return 1
  {
    printf '# fixture corpus\n\n'
    printf '%s\n' "${CORPUS_LINES[@]}"
  } >"$root/corpus.jsonl"
  git_test_config "$root" add -A >/dev/null &&
    git_test_config "$root" commit -q -m base >/dev/null
}

# prepend <file> <line>: insert <line> right after the shebang.
prepend() {
  local file=$1 line=$2
  { head -n 1 "$file" && printf '%s\n' "$line" && tail -n +2 "$file"; } >"$file.new" && mv "$file.new" "$file"
}

LAST_OUT="" LAST_ERR="" LAST_RC=0
run_check() { # <root> [env VAR=value ...] -- <args...>
  local root=$1
  shift
  local -a envs=()
  while (($#)) && [[ "$1" != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  LAST_OUT=$(cd "$root" && env ${envs[@]+"${envs[@]}"} bash scripts/check-guardrails-ps-differential.sh "$@" 2>"$root/.err")
  LAST_RC=$?
  LAST_ERR=$(<"$root/.err")
}

# expect <label> <want-rc> [<needle in stdout+stderr>]...
expect() {
  local label=$1 want=$2 needle
  shift 2
  if ((LAST_RC != want)); then
    fail "$label (rc=$LAST_RC, want $want): stdout: $LAST_OUT stderr: $LAST_ERR"
    return
  fi
  for needle in "$@"; do
    if [[ "$LAST_OUT$LAST_ERR" != *"$needle"* ]]; then
      fail "$label: missing '$needle': stdout: $LAST_OUT stderr: $LAST_ERR"
      return
    fi
  done
  ok "$label"
}

# refute <label> <needle>: <needle> must not appear in stdout+stderr.
refute() {
  if [[ "$LAST_OUT$LAST_ERR" == *"$2"* ]]; then
    fail "$1: unexpected '$2': stdout: $LAST_OUT stderr: $LAST_ERR"
  else
    ok "$1"
  fi
}

P=check-guardrails-ps-differential

# --- identical trees -----------------------------------------------------
new_fixture f || exit 1
run_check "$f" -- --corpus corpus.jsonl --jobs 4 HEAD
expect "identical trees: clean" 0 "6 commands against HEAD" "| block-dangerous-git, 31 token subsets |"
refute "identical trees: no regression line" "base exits 2, branch exits"

# --- a consumer that stops refusing --------------------------------------
# The inherited opt-out would make both arms allow everything and hide the
# regression; the check clears it.
new_fixture f || exit 1
prepend "$f/plugins/guardrails/hooks/block-dangerous-git.sh" 'exit 0'
run_check "$f" CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED=false -- --corpus corpus.jsonl --jobs 4 HEAD
expect "consumer allows: fails" 1 "$P: block-dangerous-git: base exits 2, branch exits 0: git\\ reset\\ --hard" \
  "cell(s) where HEAD refuses"

# --- the shared library, with an inherited CLAUDE_PLUGIN_ROOT --------------
# Every consumer sources the classifier from ${CLAUDE_PLUGIN_ROOT:-...}; an
# inherited root naming an unmodified copy would give both arms that copy.
new_fixture f || exit 1
cp -R "$f/plugins/guardrails" "$f/pristine"
printf '\nps::classify_git_command() { PS_SAFE_COMMAND=""; PS_SINK_TRIGGER=""; return 0; }\n' \
  >>"$f/plugins/guardrails/lib/powershell/ps-command.sh"
run_check "$f" CLAUDE_PLUGIN_ROOT="$f/pristine" -- --corpus corpus.jsonl --jobs 4 HEAD
expect "library allows: fails despite an inherited plugin root" 1 "base exits 2, branch exits 0: Write-Host\\ \\{a\\}\\;\\ git\\ reset\\ --hard"

# --- the Bash row's argv only --------------------------------------------
new_fixture f || exit 1
jq '(.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[].command) |= sub(" block-dangerous-git.sh"; "")' \
  "$f/plugins/guardrails/hooks/hooks.json" >"$f/hooks.json.new" && mv "$f/hooks.json.new" "$f/plugins/guardrails/hooks/hooks.json"
run_check "$f" -- --corpus corpus.jsonl --jobs 4 HEAD
expect "row drops a guard: fails on the row" 1 "$P: row: base exits 2, branch exits 0: git\\ reset\\ --hard"
refute "row drops a guard: direct cells unchanged" "$P: block-dangerous-git: base exits 2"

# --- a refusal only an allow token waives --------------------------------
new_fixture f || exit 1
prepend "$f/plugins/guardrails/hooks/block-dangerous-git.sh" \
  '[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW-}" == *ps-unparsable-launcher* ]] && exit 0'
run_check "$f" -- --corpus corpus.jsonl --jobs 4 HEAD
expect "token-only allow: fails in the token cells" 1 \
  "$P: block-dangerous-git with ps-unparsable-launcher: base exits 2, branch exits 0: git\\ reset\\ --hard"
refute "token-only allow: token-free cells unchanged" "$P: block-dangerous-git: base exits 2"

# --- a branch-only refusal -----------------------------------------------
new_fixture f || exit 1
prepend "$f/plugins/guardrails/hooks/block-no-verify.sh" 'exit 2'
run_check "$f" -- --corpus corpus.jsonl --jobs 4 HEAD
expect "branch-only refusal: reported, not failed" 0 "new refusal: block-no-verify: base exits 0, branch exits 2: git\\ status"

# --- --harvest -----------------------------------------------------------
# Stub suites stand in for the real ones: one sends a PowerShell payload and a
# Bash payload through a guard, the rest are absent.
new_fixture f || exit 1
find "$f/plugins/guardrails/hooks" -name '*.test.sh' -delete
cat >"$f/plugins/guardrails/hooks/block-dangerous-git.test.sh" <<'EOF'
#!/usr/bin/env bash
here=$(dirname "$0")
printf '%s' '{"tool_name":"PowerShell","hook_event_name":"PreToolUse","tool_input":{"command":"git clean -fdx\nx"}}' | bash "$here/block-dangerous-git.sh"
printf '%s' '{"tool_name":"Bash","hook_event_name":"PreToolUse","tool_input":{"command":"git clean -fdx"}}' | bash "$here/block-dangerous-git.sh"
printf '%s' '{"tool_name":"PowerShell","hook_event_name":"PreToolUse","tool_input":{"command":"git status"}}' | bash "$here/block-no-verify.sh"
exit 0
EOF
git_test_config "$f" add -A >/dev/null && git_test_config "$f" commit -q -m stubs >/dev/null
run_check "$f" -- --harvest
expect "harvest: exits 0" 0
if [[ "$LAST_OUT" == $'"git clean -fdx\\nx"\n"git status"' ]]; then
  ok "harvest: PowerShell commands only, sorted, JSON-encoded"
else
  fail "harvest output: $LAST_OUT (stderr: $LAST_ERR)"
fi
if git -C "$f" diff --quiet; then
  ok "harvest: the working tree is left untouched"
else
  fail "harvest modified the working tree: $(git -C "$f" diff --stat)"
fi
sed -i 's/"\$__hu_input"$/"$__hu_input" /' "$f/plugins/guardrails/hooks/hook-utils.sh"
run_check "$f" -- --harvest
expect "harvest: a moved anchor is an environment error" 2 "anchor in hook-utils.sh moved"

# --- usage and environment -----------------------------------------------
new_fixture f || exit 1
run_check "$f" -- --corpus corpus.jsonl
expect "no base ref: usage" 2 "usage:"
run_check "$f" -- --harvest HEAD
expect "--harvest with a ref: usage" 2 "usage:"
run_check "$f" -- --jobs 0 HEAD
expect "--jobs 0: usage" 2 "usage:"
run_check "$f" -- --bogus HEAD
expect "unknown option: usage" 2 "usage:"
run_check "$f" -- --corpus corpus.jsonl no-such-ref
expect "unresolvable ref" 2 "base ref not resolvable: no-such-ref"
run_check "$f" -- --corpus missing.jsonl HEAD
expect "missing corpus" 2 "corpus not found"
printf '{"not":"a string"}\n' >"$f/bad.jsonl"
run_check "$f" -- --corpus bad.jsonl HEAD
expect "non-string corpus line" 2 "not one JSON string per line"
printf '# only comments\n\n' >"$f/empty.jsonl"
run_check "$f" -- --corpus empty.jsonl HEAD
expect "empty corpus" 2 "corpus holds no command"

test_harness::report

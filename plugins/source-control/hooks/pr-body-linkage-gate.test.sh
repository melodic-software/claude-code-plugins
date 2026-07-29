#!/usr/bin/env bash
# Black-box contract test for pr-body-linkage-gate.sh.
#
# Proves the hook mirrors the ci-workflows pr-issue-linkage validator on the
# cases a hand port silently gets wrong — comment stripping (terminated and
# unterminated), a `## Related` section whose content is a deeper subsection,
# and the JavaScript word boundaries that make `#12abc` and `unclosed #5`
# non-matches — and that every undeterminable body ALLOWS.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures and
# invokes the hook as a subprocess from an UNRELATED cwd, so any reliance on the
# caller's working directory would surface (the hook is anchored on the payload's
# own `cwd`).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/pr-body-linkage-gate.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- pr-body-linkage-gate tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

new_repo() {
  local r="$1" gated="$2"
  mkdir -p "$r"
  git -C "$r" init -q 2>/dev/null
  if [[ "$gated" == "gated" ]]; then
    mkdir -p "$r/.github/workflows"
    printf 'name: pr-issue-linkage\n' >"$r/.github/workflows/pr-issue-linkage.yml"
  fi
}

GATED="$WORK/gated"
UNGATED="$WORK/ungated"
new_repo "$GATED" gated
new_repo "$UNGATED" plain

# run <repo> <command> -> sets RC and ERR from one hook invocation.
RC=0
ERR=""
run() {
  local repo="$1" cmd="$2" payload
  payload=$(jq -n --arg cwd "$repo" --arg cmd "$cmd" \
    '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}')
  ERR=$(cd "$UNRELATED" && printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)
  RC=$?
}

# assert_allow / assert_block <label> <repo> <command>
assert_allow() {
  run "$2" "$3"
  if ((RC == 0)); then ok "$1"; else fail "$1: expected allow, got rc=$RC ($ERR)"; fi
}
assert_block() {
  run "$2" "$3"
  if ((RC == 2)); then ok "$1"; else fail "$1: expected block(2), got rc=$RC ($ERR)"; fi
}

# gh_body <body> -> a `gh pr create` command carrying <body> as a single-quoted
# literal. Bodies in this suite never contain a single quote.
gh_body() {
  printf "gh pr create --title 'T' --body '%s'" "$1"
}

GOOD=$'Closes #5\n\n## Related\n\n- refs #9'
NO_RELATED=$'Closes #5\n\nJust a summary.'
NO_KEYWORD=$'Some summary.\n\n## Related\n\n- refs #9'

# --- Scope guard -------------------------------------------------------------

assert_allow "ungated repo: bad body allowed" "$UNGATED" "$(gh_body "$NO_RELATED")"
assert_allow "non-gh command allowed" "$GATED" "git commit -m 'x'"
assert_allow "gh command that is not pr create/edit allowed" "$GATED" "gh pr view 5"

# --- The two halves ----------------------------------------------------------

assert_allow "compliant body allowed" "$GATED" "$(gh_body "$GOOD")"
assert_block "missing ## Related blocks" "$GATED" "$(gh_body "$NO_RELATED")"
assert_block "missing closing keyword blocks" "$GATED" "$(gh_body "$NO_KEYWORD")"
assert_block "empty ## Related blocks" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related\n\n## Test plan\n\n- ran it')"

run "$GATED" "$(gh_body "$NO_RELATED")"
if [[ "$ERR" == *'Missing a "## Related" section.'* && "$ERR" == *"## Related"* && "$ERR" == *"Closes #<issue>"* ]]; then
  ok "block message names the missing half and the line to add"
else
  fail "block message lacks the missing half or the template: $ERR"
fi

# --- Closing-keyword shapes --------------------------------------------------

for kw in Closes closes Closed Fixes fix fixed Resolves resolve resolved; do
  assert_allow "keyword '$kw' accepted" "$GATED" \
    "$(gh_body "$kw #5"$'\n\n## Related\n\n- x')"
done
assert_allow "colon form accepted" "$GATED" \
  "$(gh_body $'Closes: #5\n\n## Related\n\n- x')"
assert_allow "owner/repo#N form accepted" "$GATED" \
  "$(gh_body $'Closes melodic-software/standards#5\n\n## Related\n\n- x')"
assert_allow "No linked issue marker accepted" "$GATED" \
  "$(gh_body $'No linked issue\n\n## Related\n\n- x')"
assert_allow "No related issue: marker accepted" "$GATED" \
  "$(gh_body $'No related issue: drift sweep\n\n## Related\n\n- x')"

# Word boundaries: JavaScript's \b makes both of these non-matches, so a body
# carrying only one of them must still block.
assert_block "trailing word char after #N is not a match" "$GATED" \
  "$(gh_body $'Closes #12abc\n\n## Related\n\n- x')"
assert_block "keyword glued to a preceding word is not a match" "$GATED" \
  "$(gh_body $'unclosed #5\n\n## Related\n\n- x')"

# --- HTML comments -----------------------------------------------------------

assert_block "markers only inside a terminated comment do not count" "$GATED" \
  "$(gh_body $'<!-- Closes #5 and a ## Related section -->\n\nSummary.')"
assert_block "an unterminated comment swallows the rest of the body" "$GATED" \
  "$(gh_body $'Summary.\n<!-- oops\nCloses #5\n\n## Related\n\n- x')"
assert_allow "content around a comment still counts" "$GATED" \
  "$(gh_body $'Closes #5 <!-- issue --> \n\n## Related\n<!-- list below -->\n- x')"

# --- Section boundaries ------------------------------------------------------

assert_allow "a deeper subsection is Related's content, not its terminator" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related\n\n### Prior art\n\n- x\n\n## Test plan\n\n- ran it')"
assert_block "a same-level heading terminates Related, leaving it empty" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related\n## Summary\n\n- x')"
assert_allow "Related is matched case-insensitively" "$GATED" \
  "$(gh_body $'Closes #5\n\n##   RELATED\n\n- x')"
assert_block "a Related heading with trailing text is not the section" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Related work\n\n- x')"

# --- Body sources ------------------------------------------------------------

printf '%s\n' "$NO_RELATED" >"$GATED/body.md"
assert_block "--body-file reads the file" "$GATED" "gh pr create -t T --body-file body.md"
printf '%s\n' "$GOOD" >"$GATED/good.md"
assert_allow "--body-file with a compliant file allowed" "$GATED" "gh pr create -t T -F good.md"
assert_allow "--body-file naming a missing file allowed" "$GATED" "gh pr create -t T -F absent.md"

assert_block "--body-file - reads the sole heredoc" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$NO_RELATED")"
assert_allow "--body-file - with a compliant heredoc allowed" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$GOOD")"
assert_block "--body \$(cat <<EOF) substitution is read" "$GATED" \
  "$(printf "gh pr create -t T --body \"\$(cat <<'EOF'\n%s\nEOF\n)\"\n" "$NO_RELATED")"
assert_allow "two heredocs are undeterminable" "$GATED" \
  "$(printf "cat <<'A' >x\njunk\nA\ngh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$NO_RELATED")"
assert_allow "an unterminated heredoc is undeterminable" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\n" "$NO_RELATED")"
# shellcheck disable=SC2016  # the literal, unexpanded $BODY is the fixture under test
assert_allow "a variable body is undeterminable" "$GATED" 'gh pr create -t T --body "$BODY"'
assert_allow "--fill carries no body flag" "$GATED" "gh pr create -t T --fill"
assert_allow "interactive create carries no body flag" "$GATED" "gh pr create"
assert_block "attached short-flag value is read" "$GATED" "$(printf "gh pr create -t T -b'%s'" "$NO_RELATED")"
assert_block "--body=VALUE form is read" "$GATED" "$(printf "gh pr create -t T --body='%s'" "$NO_RELATED")"
assert_block "an empty literal body blocks" "$GATED" "gh pr create -t T --body ''"
assert_allow "a trailing --body with no value is malformed, not empty" "$GATED" "gh pr create -t T --body"
assert_allow "a trailing --body-file with no value is malformed" "$GATED" "gh pr create -t T --body-file"
assert_allow "everything after -- is positional" "$GATED" "gh pr create -t T -- --body bad"
assert_allow "a body-file naming a directory is unreadable" "$GATED" "gh pr create -t T --body-file ."

# A body-shaped string sitting in another flag's value is not the body.
assert_allow "a label value spelled --body is not the body" "$GATED" \
  "gh pr create -t T -l --body --fill"

# --- gh pr edit --------------------------------------------------------------

assert_block "gh pr edit --body is gated" "$GATED" "$(printf "gh pr edit 5 --body '%s'" "$NO_RELATED")"
assert_allow "gh pr edit changing no body allowed" "$GATED" "gh pr edit 5 --add-label ready"
assert_allow "gh pr new alias with a compliant body allowed" "$GATED" \
  "$(printf "gh pr new -t T --body '%s'" "$GOOD")"

# --- Wrappers and out-of-scope targets ---------------------------------------

assert_block "env-assignment wrapper is unwrapped" "$GATED" \
  "$(printf "GH_TOKEN=x gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "env(1) wrapper is unwrapped" "$GATED" \
  "$(printf "env GH_TOKEN=x gh pr create -t T --body '%s'" "$NO_RELATED")"
assert_block "sh -c operand is re-parsed" "$GATED" \
  "$(printf "bash -c \"gh pr create -t T --body '%s'\"" "$NO_RELATED")"
assert_allow "--repo targets a repo whose gate is unknown" "$GATED" \
  "$(printf "gh pr create -R other/repo -t T --body '%s'" "$NO_RELATED")"

# --- Kill switch -------------------------------------------------------------

payload=$(jq -n --arg cwd "$GATED" --arg cmd "$(gh_body "$NO_RELATED")" \
  '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}')
if (cd "$UNRELATED" && printf '%s' "$payload" |
  CLAUDE_PLUGIN_OPTION_PR_BODY_LINKAGE_GATE_ENABLED=false bash "$HOOK" >/dev/null 2>&1); then
  ok "kill switch disables the gate"
else
  fail "kill switch did not disable the gate"
fi

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0)) || exit 1

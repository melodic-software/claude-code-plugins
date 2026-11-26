#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/*  # copies the whole hooks directory

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP=$(git -C "$HOOK_DIR" rev-parse --show-toplevel)
TOP="${TOP//$'\r'/}"
mkdir -p "$TOP/.work"
TEST_TMPDIR="$(mktemp -d "$TOP/.work/attended-veto-test.XXXXXX")"
trap 'rm -rf -- "${TEST_TMPDIR:?}"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
unset CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_ENTRYPOINT GUARDRAILS_SESSION_UNWATCHED CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR

REPO="$TEST_TMPDIR/repo"
git init -q "$REPO" || bad "fixture: could not create the repository"
PROJECT="$TEST_TMPDIR/project"
mkdir -p "$PROJECT/.claude"
SETTINGS_PAYLOAD=$(jq -n --arg fp "$PROJECT/.claude/settings.json" --arg cwd "$PROJECT" \
  '{tool_name:"Write",tool_input:{file_path:$fp,content:"{}"},cwd:$cwd}')

git_verdict() {
  local dir="$1" via="$2"
  shift 2
  guard_invoke --via "$via" --hook "$dir/block-dangerous-git.sh" --command "git reset --hard" \
    --cwd "$REPO" --chdir "$REPO" -- "$@"
  case "$GUARD_RC:$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT" 2>/dev/null)" in
  0:ask) echo ask ;;
  2:) echo deny ;;
  *) echo "other:$GUARD_RC" ;;
  esac
}

settings_verdict() {
  local dir="$1" out
  shift
  out=$(env "$@" node "$dir/settings-write-ask.mjs" <<<"$SETTINGS_PAYLOAD")
  case "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null)" in
  ask) echo ask ;;
  deny) echo deny ;;
  *) echo other ;;
  esac
}

UNSET='<unset>'
for att in "$UNSET" 0 1 true; do
  for ep in "$UNSET" cli sdk-cli claude-desktop; do
    for unw in "$UNSET" 0 1; do
      envs=(HOME="$TEST_TMPDIR/home")
      [[ $att == "$UNSET" ]] || envs+=("CLAUDE_CODE_SESSION_ATTENDED=$att")
      [[ $ep == "$UNSET" ]] || envs+=("CLAUDE_CODE_ENTRYPOINT=$ep")
      [[ $unw == "$UNSET" ]] || envs+=("GUARDRAILS_SESSION_UNWATCHED=$unw")
      old=deny
      [[ $att == 1 && $unw != 1 ]] && old=ask
      want=$old
      [[ $ep == sdk-cli ]] && want=deny
      cell="ATTENDED=$att ENTRYPOINT=$ep UNWATCHED=$unw (old $old)"
      assert_eq "block-dangerous-git: $cell" "$want" "$(git_verdict "$HOOK_DIR" direct "${envs[@]}")"
      assert_eq "run-guards: $cell" "$want" "$(git_verdict "$HOOK_DIR" dispatched "${envs[@]}")"
      assert_eq "settings-write-ask: $cell" "$want" "$(settings_verdict "$HOOK_DIR" "${envs[@]}")"
    done
  done
done

copy_without() {
  local dir="$TEST_TMPDIR/without-$1"
  cp -R "$HOOK_DIR" "$dir"
  rm -f -- "$dir/$1"
  printf '%s' "$dir"
}
copy_emptied() {
  local dir="$TEST_TMPDIR/emptied-$1"
  cp -R "$HOOK_DIR" "$dir"
  : >"$dir/$1"
  printf '%s' "$dir"
}
attended=(HOME="$TEST_TMPDIR/home" CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=cli)
assert_eq "block-dangerous-git: attended, session-attended.env deleted, denies" deny \
  "$(git_verdict "$(copy_without session-attended.env)" direct "${attended[@]}")"
assert_eq "block-dangerous-git: attended, session-attended.sh deleted, denies" deny \
  "$(git_verdict "$(copy_without session-attended.sh)" direct "${attended[@]}")"
assert_eq "settings-write-ask: attended, session-attended.mjs deleted, denies" deny \
  "$(settings_verdict "$(copy_without session-attended.mjs)" "${attended[@]}")"
assert_eq "settings-write-ask: attended, session-attended.env deleted, denies" deny \
  "$(settings_verdict "$(copy_without session-attended.env)" "${attended[@]}")"

assert_eq "block-dangerous-git: attended, session-attended.sh empty, denies" deny \
  "$(git_verdict "$(copy_emptied session-attended.sh)" direct "${attended[@]}")"
assert_eq "settings-write-ask: attended, session-attended.mjs empty, denies" deny \
  "$(settings_verdict "$(copy_emptied session-attended.mjs)" "${attended[@]}")"

echo "attended-veto: $PASS passed, $FAIL failed"
((FAIL == 0))

#!/usr/bin/env bash
# test-scope: plugins/repo-hygiene/skills/clean/SKILL.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/destructive-guard.sh"

FAILED=0
CASE_NUM=0

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

# shellcheck source=lib/run-marker.sh
source "$SCRIPT_DIR/lib/run-marker.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
export CLAUDE_PLUGIN_DATA="$TEST_ROOT/repo-hygiene"
SESSION_ID="sess-live"
LIVE_MARKER=""
run_marker_path_to LIVE_MARKER "$CLAUDE_PLUGIN_DATA" "$SESSION_ID"
run_marker_write "$LIVE_MARKER"

guard_exit() {
  jq -n --arg c "$1" --arg t "${2-Bash}" --arg s "$SESSION_ID" '{tool_name:$t, session_id:$s, tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

guard_exit_rawtool() {
  jq -n --argjson t "$1" --arg c "$2" --arg s "$SESSION_ID" '{tool_name:$t, session_id:$s, tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

guard_exit_notool() {
  jq -n --arg c "$1" --arg s "$SESSION_ID" '{session_id:$s, tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

guard_exit_session() {
  jq -n --arg c "$2" --arg s "$1" '{tool_name:"Bash", session_id:$s, tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

SKILL_MD="$(cd "$SCRIPT_DIR/.." && pwd)/SKILL.md"
MARKER_SCRIPT="$SCRIPT_DIR/clean-run-marker.sh"

help_out=$(bash "$SCRIPT" --help 2>&1)
assert_exit "--help exits 0" 0 $?
assert_contains "--help names the ack prefix" "$help_out" "CLEAN_GUARD_ACK"

for cmd in \
  "gh issue comment 7333 --body 'cleanup ran git branch -D feature/x'" \
  "gh issue create --title t --body \"run rm -rf build/ then git reset --hard\"" \
  "gh issue comment 1 --body 'git push origin --delete x and git stash drop'" \
  "gh pr comment 1 --body 'bash scripts/clean-caches.sh --apply'" \
  "echo 'git clean -fdx'" \
  "git commit -m 'drop git branch -D from the docs'" \
  "gh issue create --body-file - <<'EOF'
the body says git branch -D x and rm -rf build/
EOF"; do
  assert_exit "stays quiet on quoted text: $cmd" 0 "$(guard_exit "$cmd")"
done

for cmd in \
  "bash -c 'rm -rf build'" \
  "sh -c \"git clean -fdx\"" \
  "bash -c 'echo hi; git branch -D x'"; do
  assert_exit "blocks a shell -c operand: $cmd" 2 "$(guard_exit "$cmd")"
done
assert_exit "allows a shell -c operand that is benign" 0 "$(guard_exit "bash -c \"echo 'git branch -D'\"")"

assert_exit "still blocks a real branch delete after a quiet comment" 2 \
  "$(guard_exit "gh issue comment 1 --body 'x'; git branch -D feature/x")"

# shellcheck disable=SC2016  # the substitutions are guard input, never expanded here
nested_cmds=(
  'x="$(git stash drop)"'
  '"$(rm -rf x)"'
  'echo "`git stash drop`"'
  'x="$(echo $(git stash drop))"'
  $'echo "$(echo \'$(x)\'; git stash drop)"'
  $'cat <<EOF\n$(git stash drop)\nEOF'
  $'cat <<EOF\ndon\'t `git reset --hard`\nEOF'
  $'gh pr create --body "$(cat <<EOF\nrun `git stash drop`\nEOF\n)"'
  "sudo bash -c 'git stash drop'"
  "timeout 5 bash -c 'git stash drop'"
  "env X=1 bash -c 'git stash drop'"
  "xargs bash -c 'git stash drop'"
  "eval 'git stash drop'"
  "eval \"git reset\" --hard"
  "eval eval eval 'git stash drop'"
  "ssh h \"git stash drop\""
  "ssh -p 22 -o BatchMode=yes h 'git reset --hard'"
  "bash <<< \"git stash drop\""
  "printf 'git stash drop\n' | bash"
  "echo 'rm -rf build' | sh -s"
  "printf 'git stash drop' | sudo bash"
  "echo 'git stash drop' | ssh h"
  $'bash <<\'EOF\'\ngit stash drop\nEOF'
  $'cat <<EOF | bash\ngit reset --hard\nEOF'
  $'cat <<EOF |\n$(date)\nrm -rf ~\nEOF\nbash'
  $'ssh h <<\'EOF\'\ngit reset --hard\nEOF'
  $'X=$(true <<A\nx\nA\n) bash <<A\ngit reset --hard\nA'
  $'cat <<E\n$(cat <<F\nf\nF\n)\nE\nbash <<G\ngit reset --hard\nG'
  $'<<A\nz\nA\nbash <<A\ngit reset --hard\nA\ncat <<A\nx\\\ny\nA'
  $'<<A\nz\nA\nbash <<A\ngit reset --hard\nA\necho @(cat <<B\nb\nB\n)'
  $'!(bash <<A\ngit reset --hard\nA\n)'
  "git --git-dir /r/.git reset --hard"
  "git --work-tree /r stash drop"
)
for cmd in "${nested_cmds[@]}"; do
  assert_exit "blocks a nested or wrapped command: $cmd" 2 "$(guard_exit "$cmd")"
done

# shellcheck disable=SC2016  # the substitutions are guard input, never expanded here
literal_cmds=(
  "echo '\$(git stash drop)'"
  'echo "\$(git stash drop)"'
  'gh pr create --body "run \`git stash drop\` by hand"'
  $'cat <<\'EOF\'\n$(git stash drop) and `rm -rf x`\nEOF'
  $'cat <<EOF\ndon\'t run git branch -D x\nEOF'
  $'gh pr create --body "$(cat <<\'EOF\'\n1) don\'t run `git stash drop` (see "#1"\nEOF\n)"'
  "echo \$'\$(git stash drop)'"
  "eval 'echo hi'"
  "ssh h ls"
  "ssh -l h 'git stash drop'"
  "printf 'git status\n' | bash"
  $'bash <<\'EOF\'\necho hi\nEOF'
  $'cat <<A\ndocs\nA\nbash <<B\necho hi\nB'
  $'cat <<\'EOF\' > notes.md\ngit stash drop\nEOF'
  "echo 'rm -rf build' | tee bash"
  "bash scripts/x.sh <<< 'git stash drop'"
  "git --git-dir /r/.git status"
)
for cmd in "${literal_cmds[@]}"; do
  assert_exit "stays quiet on text bash does not run: $cmd" 0 "$(guard_exit "$cmd")"
done

assert_exit "PowerShell tool blocks a git global option with a separate value" 2 \
  "$(guard_exit "git --git-dir /r/.git reset --hard" PowerShell)"

parsed_words="$(
  # shellcheck source=hook-utils.sh
  source "$SCRIPT_DIR/hook-utils.sh"
  # shellcheck disable=SC2329  # invoked indirectly as the parser callback
  report() { printf '%s|' "$#" "$5"; }
  hook::bash_parse_segments "gh issue comment --body 'git branch -D x'" report
)"
assert_contains "generated hook-utils copy parses a quoted argument as one word" "$parsed_words" "5|git branch -D x|"

rm -f "$LIVE_MARKER"
assert_exit "no marker: git branch -D x is allowed" 0 "$(guard_exit "git branch -D x")"
assert_exit "no marker: rm -rf is allowed" 0 "$(guard_exit "rm -rf build/")"
assert_exit "no marker: PowerShell Remove-Item is allowed" 0 "$(guard_exit "Remove-Item -Recurse -Force obj" PowerShell)"

run_marker_write "$LIVE_MARKER"
assert_exit "live marker: git branch -D x is blocked" 2 "$(guard_exit "git branch -D x")"
assert_exit "live marker: another session is not gated" 0 "$(guard_exit_session "sess-other" "git branch -D x")"
assert_exit "live marker: unusable session id keeps the guard armed" 2 "$(guard_exit_session "../escape" "git branch -D x")"

printf '1\n' >"$LIVE_MARKER"
assert_exit "stale marker: git branch -D x is allowed" 0 "$(guard_exit "git branch -D x")"
if [[ -e "$LIVE_MARKER" ]]; then
  fail "stale marker is removed" "removed" "present"
else
  pass "stale marker is removed"
fi

nearly_idle=$(($(printf '%(%s)T' -1) - RUN_MARKER_IDLE_SECONDS + 60))
printf '%s\n' "$nearly_idle" >"$LIVE_MARKER"
assert_exit "nearly idle marker: still blocks" 2 "$(guard_exit "git branch -D x")"
read -r refreshed <"$LIVE_MARKER"
if ((refreshed >= $(printf '%(%s)T' -1) - 5)); then
  pass "a blocked destructive call refreshes the marker"
else
  fail "a blocked destructive call refreshes the marker" "within 5s of now" "$refreshed"
fi

printf '%s\n' "$nearly_idle" >"$LIVE_MARKER"
assert_exit "nearly idle marker: acknowledged call is allowed" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git branch -D x")"
read -r refreshed <"$LIVE_MARKER"
if ((refreshed >= $(printf '%(%s)T' -1) - 5)); then
  pass "an acknowledged call refreshes the marker"
else
  fail "an acknowledged call refreshes the marker" "within 5s of now" "$refreshed"
fi

printf '%s\n' "$nearly_idle" >"$LIVE_MARKER"
assert_exit "nearly idle marker: ordinary call is allowed" 0 "$(guard_exit "git status")"
read -r refreshed <"$LIVE_MARKER"
if [[ "$refreshed" == "$nearly_idle" ]]; then
  pass "an ordinary call does not refresh the marker"
else
  fail "an ordinary call does not refresh the marker" "$nearly_idle" "$refreshed"
fi

printf '%s\n' "$nearly_idle" >"$LIVE_MARKER"
assert_exit "nearly idle marker: skill-script dry-run is allowed" 0 \
  "$(guard_exit "bash /p/skills/clean/scripts/clean-caches.sh --dry-run --repo /r")"
read -r refreshed <"$LIVE_MARKER"
if ((refreshed >= $(printf '%(%s)T' -1) - 5)); then
  pass "a skill-script dry-run refreshes the marker"
else
  fail "a skill-script dry-run refreshes the marker" "within 5s of now" "$refreshed"
fi

printf '1\n' >"$LIVE_MARKER"
assert_exit "stale marker: a skill-script call means the run is still going (an hour-long confirmation gate), so its apply stays blocked" 2 \
  "$(guard_exit "bash scripts/clean-caches.sh --apply --manifest /m")"
assert_file_exists "stale marker: a skill-script call keeps the marker" "$LIVE_MARKER"

mention_cmds=(
  "git add plugins/repo-hygiene/skills/clean/scripts/clean-batch.sh"
  "grep -n apply clean-batch.sh" # portability-ok: a test command string, never executed
  "sudo bash scripts/clean-caches.sh --dry-run"
)
for cmd in "${mention_cmds[@]}"; do
  printf '%s\n' "$nearly_idle" >"$LIVE_MARKER"
  guard_exit "$cmd" >/dev/null
  read -r refreshed <"$LIVE_MARKER"
  if [[ "$refreshed" == "$nearly_idle" ]]; then
    pass "a script mention does not refresh the marker: $cmd"
  else
    fail "a script mention does not refresh the marker: $cmd" "$nearly_idle" "$refreshed"
  fi
done

printf '%s\n' "$nearly_idle" >"$LIVE_MARKER"
guard_exit "bash -c 'bash scripts/clean-caches.sh --dry-run'" >/dev/null
read -r refreshed <"$LIVE_MARKER"
if ((refreshed >= $(printf '%(%s)T' -1) - 5)); then
  pass "a skill-script dry-run inside bash -c refreshes the marker"
else
  fail "a skill-script dry-run inside bash -c refreshes the marker" "within 5s of now" "$refreshed"
fi

printf '1\n' >"$LIVE_MARKER"
assert_exit "stale marker: a comment naming a script is allowed" 0 \
  "$(guard_exit "gh issue comment 1 --body 'see clean-caches.sh'")"
assert_file_absent "stale marker: a comment naming a script removes it" "$LIVE_MARKER"

printf 'garbage\n' >"$LIVE_MARKER"
assert_exit "unreadable marker: still blocks" 2 "$(guard_exit "git branch -D x")"

unresolved=$(
  jq -n --arg s "$SESSION_ID" '{tool_name:"Bash", session_id:$s, tool_input:{command:"git branch -D x"}}' |
    CLAUDE_PLUGIN_DATA="" bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "unset CLAUDE_PLUGIN_DATA keeps the guard armed" 2 "$unresolved"

data_dir_exit() {
  jq -n --arg s "$SESSION_ID" '{tool_name:"Bash", session_id:$s, tool_input:{command:"git branch -D x"}}' |
    CLAUDE_PLUGIN_DATA="$1" bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}
assert_exit "another plugin's CLAUDE_PLUGIN_DATA keeps the guard armed" 2 "$(data_dir_exit "$TEST_ROOT/other-plugin")"
assert_exit "a CLAUDE_PLUGIN_DATA under a repo-hygiene-x dir keeps the guard armed" 2 \
  "$(data_dir_exit "$TEST_ROOT/repo-hygiene-x/other-plugin")"
assert_exit "repo-hygiene-<marketplace> data dir with no marker allows" 0 \
  "$(data_dir_exit "$TEST_ROOT/repo-hygiene-market")"
assert_exit "repo-hygiene-<marketplace> data dir with a trailing slash and no marker allows" 0 \
  "$(data_dir_exit "$TEST_ROOT/repo-hygiene-market/")"

NOHU_DIR="$TEST_ROOT/no-hook-utils"
mkdir -p "$NOHU_DIR/lib"
cp "$SCRIPT" "$NOHU_DIR/destructive-guard.sh"
cp "$SCRIPT_DIR/lib/run-marker.sh" "$NOHU_DIR/lib/run-marker.sh"
no_hook_utils=$(
  jq -n --arg s "$SESSION_ID" '{tool_name:"Bash", session_id:$s, tool_input:{command:"git stash drop"}}' |
    bash "$NOHU_DIR/destructive-guard.sh" >/dev/null 2>&1
  echo $?
)
assert_exit "missing hook-utils.sh exits 2" 2 "$no_hook_utils"
no_session=$(
  jq -n '{tool_name:"Bash", tool_input:{command:"git branch -D x"}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "missing session_id keeps the guard armed" 2 "$no_session"
run_marker_write "$LIVE_MARKER"

for tier in scan scan-batch; do
  bash "$MARKER_SCRIPT" open --tier "$tier" --session "sess-$tier" --data-dir "$CLAUDE_PLUGIN_DATA" >/dev/null 2>&1
  assert_exit "open --tier $tier exits 0" 0 $?
  if [[ -e "$CLAUDE_PLUGIN_DATA/clean-run/sess-$tier.open" ]]; then
    fail "open --tier $tier writes no marker" "absent" "present"
  else
    pass "open --tier $tier writes no marker"
  fi
done
for tier in caches build git stash tree all caches-batch tree-batch; do
  bash "$MARKER_SCRIPT" open --tier "$tier" --session "sess-$tier" --data-dir "$CLAUDE_PLUGIN_DATA" >/dev/null 2>&1
  assert_exit "open --tier $tier exits 0" 0 $?
  if [[ -e "$CLAUDE_PLUGIN_DATA/clean-run/sess-$tier.open" ]]; then
    pass "open --tier $tier writes the marker"
  else
    fail "open --tier $tier writes the marker" "present" "absent"
  fi
done
assert_exit "marker armed by the script gates the guard" 2 "$(guard_exit_session "sess-caches" "git branch -D x")"
bash "$MARKER_SCRIPT" close --session "sess-caches" --data-dir "$CLAUDE_PLUGIN_DATA" >/dev/null 2>&1
assert_exit "close exits 0" 0 $?
assert_exit "closed run: the guard lets git branch -D x through" 0 "$(guard_exit_session "sess-caches" "git branch -D x")"
bash "$MARKER_SCRIPT" close --session "sess-caches" --data-dir "$CLAUDE_PLUGIN_DATA" >/dev/null 2>&1
assert_exit "close is idempotent" 0 $?
bash "$MARKER_SCRIPT" open --tier caches --session "sess-x" --data-dir '${CLAUDE_PLUGIN_DATA}' >/dev/null 2>&1
assert_exit "open refuses an unsubstituted data dir" 2 $?
bash "$MARKER_SCRIPT" open --tier caches --session "../x" --data-dir "$CLAUDE_PLUGIN_DATA" >/dev/null 2>&1
assert_exit "open refuses an unusable session id" 2 $?
bash "$MARKER_SCRIPT" open --session "sess-x" --data-dir "$CLAUDE_PLUGIN_DATA" >/dev/null 2>&1
assert_exit "open without --tier is a usage error" 2 $?

for cmd in \
  "rm -rf build/" \
  "rm -Rf build/" \
  "rm -r -f build/" \
  "rm -f -r build/" \
  "rm --recursive --force build/" \
  "git clean -fdx" \
  "git clean --force -d" \
  "git -C /tmp/x clean -fdx" \
  "git --git-dir=/tmp/x/.git clean -f" \
  "git -c gc.auto=0 clean -f" \
  "git -C /tmp/x reset --hard origin/main" \
  "git reset --hard origin/main" \
  "git checkout -- ." \
  "git -C /tmp/x checkout -- ." \
  "git stash drop" \
  "git stash drop stash@{0}" \
  "git stash clear" \
  "git -C /tmp/x stash drop" \
  "Remove-Item -Recurse -Force obj"; do
  assert_exit "blocks: $cmd" 2 "$(guard_exit "$cmd")"
done

registered_matcher="$(awk '
  /^---[[:space:]]*$/ { fm++; next }
  fm == 1 && /^[[:space:]]*-[[:space:]]*matcher:/ { m = $0 }
  fm == 1 && /destructive-guard\.sh/ && m != "" { print m; exit }
' "$SKILL_MD")"
assert_contains "hook registration reaches the Bash tool" "$registered_matcher" "Bash"
assert_contains "hook registration reaches the PowerShell tool" "$registered_matcher" "PowerShell"

for cmd in \
  "Remove-Item -Recurse -Force obj" \
  "Remove-Item -Force -Recurse bin" \
  "Remove-Item -Path build -Recurse -Force"; do
  assert_exit "blocks via PowerShell tool: $cmd" 2 "$(guard_exit "$cmd" PowerShell)"
done

assert_exit "allows benign PowerShell tool call" 0 "$(guard_exit "Get-ChildItem -Recurse" PowerShell)"

# shellcheck disable=SC2016  # literal `$env:` is the PowerShell spelling
ps_ack='$env:CLEAN_GUARD_ACK=1;'
for cmd in \
  "$ps_ack Remove-Item -Recurse -Force obj" \
  "$ps_ack git stash drop 'stash@{0}'" \
  "$ps_ack git reset --hard origin/main" \
  "\$env:CLEAN_GUARD_ACK=\"1\"; Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK = '1' ; Remove-Item -Recurse -Force obj"; do
  assert_exit "PowerShell ack allows: $cmd" 0 "$(guard_exit "$cmd" PowerShell)"
done

if command -v pwsh >/dev/null 2>&1; then
  ps_seen="$(pwsh -NoProfile -NonInteractive -Command "$ps_ack Write-Output \"ack=\$env:CLEAN_GUARD_ACK\"" 2>/dev/null)"
  assert_contains "pwsh executes the accepted ack spelling and the value reaches the command" "$ps_seen" "ack=1"
  pwsh -NoProfile -NonInteractive -Command 'CLEAN_GUARD_ACK=1 Write-Output hi' >/dev/null 2>&1
  assert_exit "pwsh cannot execute the Bash ack spelling" 1 $?

  PS_FIX="$(mktemp -d)"
  ps_git=(git -C "$PS_FIX" -c user.email=t@example.invalid -c user.name=t)
  if git init -q "$PS_FIX" 2>/dev/null &&
    "${ps_git[@]}" commit -q --allow-empty -m base 2>/dev/null; then
    stash_count() { git -C "$PS_FIX" stash list | wc -l | tr -d '[:space:]'; }
    make_stash() {
      printf '%s\n' "$1" >"$PS_FIX/f.txt"
      "${ps_git[@]}" add f.txt
      "${ps_git[@]}" stash push -q -m "$1"
    }
    make_stash one
    make_stash two
    before="$(stash_count)"

    PS_FIX_NATIVE="$(cygpath -m "$PS_FIX" 2>/dev/null || printf '%s' "$PS_FIX")"

    pwsh -NoProfile -NonInteractive -Command \
      "\$env:CLEAN_GUARD_ACK=1; git -C '$PS_FIX_NATIVE' stash drop stash@{0}" >/dev/null 2>&1
    unquoted_rc=$?
    assert_exit "pwsh: unquoted stash selector fails" nonzero \
      "$([[ $unquoted_rc -ne 0 ]] && echo nonzero || echo "zero")"
    assert_exit "pwsh: unquoted stash selector drops nothing" "$before" "$(stash_count)"

    pwsh -NoProfile -NonInteractive -Command \
      "\$env:CLEAN_GUARD_ACK=1; git -C '$PS_FIX_NATIVE' stash drop 'stash@{0}'" >/dev/null 2>&1
    assert_exit "pwsh: quoted stash selector succeeds" 0 $?
    assert_exit "pwsh: quoted stash selector drops one stash" "$((before - 1))" "$(stash_count)"
  else
    skip_case "pwsh stash-selector cases: git fixture could not be created"
  fi
  rm -rf "$PS_FIX"
else
  skip_case "pwsh not on PATH: live execution of the PowerShell ack spelling not verified"
fi

for cmd in \
  "Remove-Item -Recurse -Force obj # $ps_ack" \
  "# $ps_ack Remove-Item -Recurse -Force obj" \
  "Write-Host \"$ps_ack\"; Remove-Item -Recurse -Force obj" \
  "'$ps_ack'; Remove-Item -Recurse -Force obj" \
  "Remove-Item -Recurse -Force obj; \$env:CLEAN_GUARD_ACK=1" \
  "Get-ChildItem | ForEach-Object { \$env:CLEAN_GUARD_ACK=1 }; Remove-Item -Recurse -Force obj" \
  "Get-Location; $ps_ack Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK=0; Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK=''; Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK=\$null; Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK=10; Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK=1 Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK=1 | Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACKX=1; Remove-Item -Recurse -Force obj" \
  "\$env:CLEAN_GUARD_ACK=\"1; Remove-Item -Recurse -Force obj\"" \
  "CLEAN_GUARD_ACK=1 Remove-Item -Recurse -Force obj"; do
  assert_exit "PowerShell ack does not bypass: $cmd" 2 "$(guard_exit "$cmd" PowerShell)"
done

assert_exit "PowerShell ack spelling is not an ack on the Bash tool" 2 "$(guard_exit "$ps_ack git stash drop" Bash)"
assert_exit "Bash ack is not accepted inside a comment" 2 "$(guard_exit "git stash drop # CLEAN_GUARD_ACK=1" Bash)"
assert_exit "Bash ack is not accepted after the command" 2 "$(guard_exit "git stash drop stash@{0}; CLEAN_GUARD_ACK=1" Bash)"

ps_reason=$(jq -n '{tool_name:"PowerShell",tool_input:{command:"Remove-Item -Recurse -Force obj"}}' | bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "PowerShell block reason names the PowerShell ack spelling" "$ps_reason" "$ps_ack"

ungated_tools=(Foo powershell Powershell "PowerShell " " Bash" "bash" "Bash2" "123" "null" "")
for tool in "${ungated_tools[@]}"; do
  label="tool_name '${tool}'"
  [[ -n "$tool" ]] || label="tool_name empty string"
  assert_exit "$label: bare destructive still blocked" 2 "$(guard_exit "git stash drop" "$tool")"
  assert_exit "$label: Bash ack prefix grants nothing" 2 "$(guard_exit "CLEAN_GUARD_ACK=1 git clean -fdx" "$tool")"
  assert_exit "$label: PowerShell ack spelling grants nothing" 2 \
    "$(guard_exit "$ps_ack Remove-Item -Recurse -Force obj" "$tool")"
  assert_exit "$label: benign command still allowed" 0 "$(guard_exit "git status" "$tool")"
done

assert_exit "tool_name null: bare destructive still blocked" 2 "$(guard_exit_rawtool null "git stash drop")"
assert_exit "tool_name null: Bash ack prefix grants nothing" 2 "$(guard_exit_rawtool null "CLEAN_GUARD_ACK=1 git clean -fdx")"
assert_exit "tool_name 123: bare destructive still blocked" 2 "$(guard_exit_rawtool 123 "git stash drop")"
assert_exit "tool_name 123: Bash ack prefix grants nothing" 2 "$(guard_exit_rawtool 123 "CLEAN_GUARD_ACK=1 git clean -fdx")"
assert_exit "tool_name absent: bare destructive still blocked" 2 "$(guard_exit_notool "git stash drop")"
assert_exit "tool_name absent: Bash ack prefix grants nothing" 2 "$(guard_exit_notool "CLEAN_GUARD_ACK=1 git clean -fdx")"
assert_exit "tool_name absent: PowerShell ack spelling grants nothing" 2 \
  "$(guard_exit_notool "$ps_ack Remove-Item -Recurse -Force obj")"
assert_exit "tool_name absent: benign command still allowed" 0 "$(guard_exit_notool "git status")"

ungated_reason=$(jq -n '{tool_name:"Foo",tool_input:{command:"git clean -fdx"}}' | bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "ungated tool block reason names the guard" "$ungated_reason" "destructive guard"
assert_contains "ungated tool block reason says there is no ack path" "$ungated_reason" "no acknowledgement path"
assert_not_contains "ungated tool block reason offers no ack spelling" "$ungated_reason" "CLEAN_GUARD_ACK"

for cmd in \
  "bash /d/plugins/clean-batch.sh --tier all --apply --batch-plan /tmp/p" \
  "bash scripts/remove-path.sh --apply /d/repos/foo" \
  "bash \"scripts/remove-path.sh\" --apply /d/repos/foo" \
  "bash scripts/remove-path.sh '--apply' /d/repos/foo" \
  "bash scripts/clean-caches.sh --apply; echo done" \
  "bash scripts/clean-caches.sh --apply;true" \
  "bash scripts/git-prune.sh --apply&&echo done" \
  "(bash scripts/remove-path.sh --apply /d/repos/foo)" \
  "bash scripts/clean-build.sh --apply&" \
  "git worktree remove --force;true" \
  "bash scripts/git-tree-reset.sh --apply" \
  "bash scripts/git-tree-reset-batch.sh --apply" \
  "bash scripts/clean-caches.sh --apply --manifest /tmp/m" \
  "bash scripts/clean-build.sh --apply --include-caches --manifest /tmp/m" \
  "bash scripts/git-prune.sh --apply" \
  "git worktree remove --force /d/worktrees/x" \
  "git worktree remove -f /d/worktrees/x" \
  "git -C /d/repo worktree remove --force /d/worktrees/x" \
  "git branch -D feature/x" \
  "git branch -d feature/x" \
  "git branch --delete --force x" \
  "git branch -df x" \
  "git branch -fd x" \
  "git branch -vD x" \
  "git -C /d/repo branch -D x" \
  "git --no-pager branch -D x" \
  "git -p branch -D x" \
  "git --no-pager clean -fd" \
  "git branch \"-d\" x" \
  "git branch a b -D" \
  "git branch --merged | xargs git branch -d" \
  "git push origin --delete feature/x" \
  "git push origin --delete refs/heads/feature/x" \
  "git push --delete origin x" \
  "git push -d origin x" \
  "git push origin :feature/x" \
  "git push origin :refs/heads/x" \
  "git push origin ':feature/x'" \
  "git -C /d/repo push origin --delete x" \
  "git --no-optional-locks push origin --delete x" \
  "git push origin +:refs/heads/x" \
  "git push origin +:feature/x" \
  "git push origin \"+:refs/heads/x\"" \
  "git push origin '+:refs/heads/x'" \
  "git push origin \"--delete\" x" \
  "git push origin '--delete' x" \
  "git push origin --delete -oconfirmed x" \
  "git push --dry-run origin main; git push origin --delete x" \
  "git push -d origin x; ls -n"; do
  assert_exit "blocks: $cmd" 2 "$(guard_exit "$cmd")"
done

assert_exit "blocks a quoted backslash script path" 2 \
  "$(guard_exit "bash 'scripts\\clean-caches.sh' --apply")"

for cmd in \
  "bash scripts/clean-batch.sh --tier caches --dry-run --repo /d/repos/foo" \
  "bash scripts/remove-path.sh --dry-run /d/repos/foo" \
  "bash scripts/git-tree-reset.sh --dry-run" \
  "git worktree remove /d/worktrees/x" \
  "git branch" \
  "git branch -a" \
  "git branch -r" \
  "git branch -vv" \
  "git branch --list" \
  "git branch --list 'feature/*'" \
  "git branch --show-current" \
  "git branch --merged main" \
  "git branch --sort=-committerdate" \
  "git branch -m old new" \
  "git branch -c old new" \
  "git branch -u origin/main" \
  "git branch feature-d" \
  "git branch -a; ls -d /tmp" \
  "git branch --merged | xargs -d x echo" \
  "git -C /d/repo branch -a" \
  "git --no-pager branch -a" \
  "git push" \
  "git push -oconfirmed origin main" \
  "git push origin main" \
  "git push origin HEAD:refs/heads/x" \
  "git push -u origin feature-d" \
  "git push --force-with-lease origin x" \
  "git push --delete --dry-run origin x" \
  "git push -d -n origin x" \
  "git push -dn origin x" \
  "git push origin :"; do
  assert_exit "allows (not matched by is_destructive): $cmd" 0 "$(guard_exit "$cmd")"
done

assert_exit "ack prefix allows clean-batch --apply" 0 \
  "$(guard_exit "CLEAN_GUARD_ACK=1 bash scripts/clean-batch.sh --tier all --apply --batch-plan /tmp/p")"
assert_exit "PowerShell ack allows remove-path --apply" 0 \
  "$(guard_exit "$ps_ack bash scripts/remove-path.sh --apply /d/repos/foo" PowerShell)"
assert_exit "ack prefix allows git branch -D" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git branch -D x")"
assert_exit "ack prefix allows git push --delete" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git push origin --delete x")"
assert_exit "PowerShell ack allows git branch -D" 0 "$(guard_exit "$ps_ack git branch -D x" PowerShell)"
assert_exit "PowerShell tool blocks git branch -D without the ack" 2 "$(guard_exit "git branch -D x" PowerShell)"
assert_exit "Bash ack prefix grants nothing to git branch -D on an ungated tool" 2 "$(guard_exit "CLEAN_GUARD_ACK=1 git branch -D x" Foo)"

reason=$(jq -n '{tool_name:"Bash",tool_input:{command:"git clean -fdx"}}' | bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "block reason names the guard" "$reason" "destructive guard"
assert_contains "block reason names the ack path" "$reason" "CLEAN_GUARD_ACK=1"

assert_exit "ack prefix allows git clean" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git clean -fdx -e node_modules/")"
assert_exit "ack prefix allows reset --hard" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git reset --hard origin/main")"
assert_exit "ack prefix allows stash drop" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git stash drop stash@{1}")"

for cmd in "git status" "rm file.txt" "git clean -n" "git clean -nx" "git clean -x" "ls -rf" "dotnet build" "git stash list" "git stash show stash@{0}"; do
  assert_exit "allows: $cmd" 0 "$(guard_exit "$cmd")"
done

killed=$(
  jq -n '{tool_input:{command:"git clean -fdx"}}' | CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED=false bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "kill switch allows everything" 0 "$killed"

empty=$(
  printf '{}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "empty tool_input exits 0" 0 "$empty"

NOJQ_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT" "$NOJQ_DIR"' EXIT
for bin in bash cat grep sed; do
  ln -s "$(command -v "$bin")" "$NOJQ_DIR/$bin" 2>/dev/null || true
done

nojq_exit() {
  printf '{"tool_input":{"command":"%s"}}' "$1" | PATH="$NOJQ_DIR" "$NOJQ_DIR/bash" "$SCRIPT" >/dev/null 2>&1
  echo $?
}

if [[ "$(PATH="$NOJQ_DIR" "$NOJQ_DIR/bash" -c 'command -v jq >/dev/null 2>&1 && echo have-jq; echo ok' 2>/dev/null)" == "ok" ]]; then
  assert_exit "no jq: blocks raw destructive payload" 2 "$(nojq_exit "git clean -fdx")"
  assert_exit "no jq: blocks rm -rf payload" 2 "$(nojq_exit "rm -rf build/")"
  assert_exit "no jq: blocks git branch -D payload" 2 "$(nojq_exit "git branch -D x")"
  assert_exit "no jq: blocks git push --delete payload" 2 "$(nojq_exit "git push origin --delete x")"
  assert_exit "no jq: benign push payload passes" 0 "$(nojq_exit "git push origin main")"
  assert_exit "no jq: benign payload passes" 0 "$(nojq_exit "git status")"
  assert_exit "no jq: ack prefix does NOT bypass (unverifiable)" 2 "$(nojq_exit "CLEAN_GUARD_ACK=1 git clean -fdx")"
  assert_exit "no jq: PowerShell ack does NOT bypass (unverifiable)" 2 "$(nojq_exit "$ps_ack Remove-Item -Recurse -Force obj")"
  reason=$(printf '{"tool_input":{"command":"git clean -fdx"}}' | PATH="$NOJQ_DIR" "$NOJQ_DIR/bash" "$SCRIPT" 2>&1 >/dev/null)
  assert_contains "no jq: block reason names degraded mode" "$reason" "degraded mode: jq not found"
else
  skip_case "degraded-mode cases: PATH sandbox not functional on this platform"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1

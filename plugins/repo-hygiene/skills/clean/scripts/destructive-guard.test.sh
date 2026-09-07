#!/usr/bin/env bash
# Regression tests for destructive-guard.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/destructive-guard.sh"

FAILED=0
CASE_NUM=0

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

# guard_exit <command> [tool_name] — omitting the tool defaults to Bash; passing
# an explicit empty string sends an empty tool_name (`${2-…}`, not `${2:-…}`).
guard_exit() {
  jq -n --arg c "$1" --arg t "${2-Bash}" '{tool_name:$t, tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

# guard_exit_rawtool <json-tool-value> <command> — tool_name as a raw JSON value,
# so non-string payloads (null, a number) reach the guard as themselves.
guard_exit_rawtool() {
  jq -n --argjson t "$1" --arg c "$2" '{tool_name:$t, tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

# guard_exit_notool <command> — payload with no tool_name key at all.
guard_exit_notool() {
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

SKILL_MD="$(cd "$SCRIPT_DIR/.." && pwd)/SKILL.md"

# --- 1. --help contract --------------------------------------------------------

help_out=$(bash "$SCRIPT" --help 2>&1)
assert_exit "--help exits 0" 0 $?
assert_contains "--help names the ack prefix" "$help_out" "CLEAN_GUARD_ACK"

# --- 2. Destructive commands blocked (exit 2) -----------------------------------

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

# --- 2b. PowerShell coverage: registration AND verdict, end to end ---------------
# The guard has always carried a PowerShell spelling (recursive `Remove-Item`),
# but a `Bash`-only matcher can never hand it a PowerShell tool call, so that
# pattern was unreachable and on a PowerShell host the guard was simply absent.
# Both halves are asserted here. Asserting only the verdict would pass with the
# bug fully intact, since the guard script itself was never the broken part.

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

# --- 2c. PowerShell acknowledgement: a spelling PowerShell can actually run ------
# `CLEAN_GUARD_ACK=1 <cmd>` is Bash syntax; pwsh rejects it ("term
# 'CLEAN_GUARD_ACK=1' is not recognized"), so accepting it on the PowerShell
# tool would assert an ack path that does not exist. The accepted spelling is
# the `$env:` assignment as the FIRST statement, terminated by `;`. When pwsh is
# on PATH, the spelling is executed for real to keep this case honest.

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

  # The stash selector needs quoting on the PowerShell lane. Bare `stash@{0}` is
  # splatting syntax to pwsh, so git receives a mangled argument and reports
  # "unknown switch `e'" without dropping anything. The guard accepts either
  # spelling (the ack prefix is identical), so only a live run tells them apart.
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

    pwsh -NoProfile -NonInteractive -Command \
      "\$env:CLEAN_GUARD_ACK=1; git -C '$PS_FIX' stash drop stash@{0}" >/dev/null 2>&1
    unquoted_rc=$?
    assert_exit "pwsh: unquoted stash selector fails" nonzero \
      "$([[ $unquoted_rc -ne 0 ]] && echo nonzero || echo "zero")"
    assert_exit "pwsh: unquoted stash selector drops nothing" "$before" "$(stash_count)"

    pwsh -NoProfile -NonInteractive -Command \
      "\$env:CLEAN_GUARD_ACK=1; git -C '$PS_FIX' stash drop 'stash@{0}'" >/dev/null 2>&1
    assert_exit "pwsh: quoted stash selector succeeds" 0 $?
    assert_exit "pwsh: quoted stash selector drops one stash" "$((before - 1))" "$(stash_count)"
  else
    skip_case "pwsh stash-selector cases: git fixture could not be created"
  fi
  rm -rf "$PS_FIX"
else
  skip_case "pwsh not on PATH: live execution of the PowerShell ack spelling not verified"
fi

# The ack is a deny-to-allow widening: it counts only as the leading statement
# with a truthy literal value. None of these may unblock a destructive command.
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

# The PowerShell spelling is not an assignment in Bash (`$env` expands empty,
# `:CLEAN_GUARD_ACK=1` is a failed command lookup, and the command still runs).
assert_exit "PowerShell ack spelling is not an ack on the Bash tool" 2 "$(guard_exit "$ps_ack git stash drop" Bash)"
assert_exit "Bash ack is not accepted inside a comment" 2 "$(guard_exit "git stash drop # CLEAN_GUARD_ACK=1" Bash)"
assert_exit "Bash ack is not accepted after the command" 2 "$(guard_exit "git stash drop stash@{0}; CLEAN_GUARD_ACK=1" Bash)"

ps_reason=$(jq -n '{tool_name:"PowerShell",tool_input:{command:"Remove-Item -Recurse -Force obj"}}' | bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "PowerShell block reason names the PowerShell ack spelling" "$ps_reason" "$ps_ack"

# --- 2d. Tool gating: each ack spelling counts only on its own tool ---------------
# The dispatch is default-deny on `tool_name`: `Bash` gets the prefix spelling,
# `PowerShell` gets the `$env:` spelling, and anything else gets no ack path at
# all. Matching on "not PowerShell" instead would silently hand the Bash ack to
# every tool added later, including one whose shell cannot run it. Blocking is
# unchanged for all of them: a bare destructive command still exits 2, and a
# benign one still exits 0.

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

# tool_name present but not a string, and tool_name absent entirely.
assert_exit "tool_name null: bare destructive still blocked" 2 "$(guard_exit_rawtool null "git stash drop")"
assert_exit "tool_name null: Bash ack prefix grants nothing" 2 "$(guard_exit_rawtool null "CLEAN_GUARD_ACK=1 git clean -fdx")"
assert_exit "tool_name 123: bare destructive still blocked" 2 "$(guard_exit_rawtool 123 "git stash drop")"
assert_exit "tool_name 123: Bash ack prefix grants nothing" 2 "$(guard_exit_rawtool 123 "CLEAN_GUARD_ACK=1 git clean -fdx")"
assert_exit "tool_name absent: bare destructive still blocked" 2 "$(guard_exit_notool "git stash drop")"
assert_exit "tool_name absent: Bash ack prefix grants nothing" 2 "$(guard_exit_notool "CLEAN_GUARD_ACK=1 git clean -fdx")"
assert_exit "tool_name absent: PowerShell ack spelling grants nothing" 2 \
  "$(guard_exit_notool "$ps_ack Remove-Item -Recurse -Force obj")"
assert_exit "tool_name absent: benign command still allowed" 0 "$(guard_exit_notool "git status")"

# The block reason for an ungated tool offers no prefix to retry with, rather
# than naming a spelling that tool cannot honour.
ungated_reason=$(jq -n '{tool_name:"Foo",tool_input:{command:"git clean -fdx"}}' | bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "ungated tool block reason names the guard" "$ungated_reason" "destructive guard"
assert_contains "ungated tool block reason says there is no ack path" "$ungated_reason" "no acknowledgement path"
assert_not_contains "ungated tool block reason offers no ack spelling" "$ungated_reason" "CLEAN_GUARD_ACK"

# --- 3. Block reason reaches stderr ----------------------------------------------

reason=$(jq -n '{tool_name:"Bash",tool_input:{command:"git clean -fdx"}}' | bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "block reason names the guard" "$reason" "destructive guard"
assert_contains "block reason names the ack path" "$reason" "CLEAN_GUARD_ACK=1"

# --- 4. Acknowledged commands allowed --------------------------------------------

assert_exit "ack prefix allows git clean" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git clean -fdx -e node_modules/")"
assert_exit "ack prefix allows reset --hard" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git reset --hard origin/main")"
assert_exit "ack prefix allows stash drop" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git stash drop stash@{1}")"

# --- 5. Benign commands pass -----------------------------------------------------

for cmd in "git status" "rm file.txt" "git clean -n" "git clean -nx" "git clean -x" "ls -rf" "dotnet build" "git stash list" "git stash show stash@{0}"; do
  assert_exit "allows: $cmd" 0 "$(guard_exit "$cmd")"
done

# --- 6. Kill switch --------------------------------------------------------------

killed=$(
  jq -n '{tool_input:{command:"git clean -fdx"}}' | CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED=false bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "kill switch allows everything" 0 "$killed"

# --- 7. Non-Bash / empty input tolerated ------------------------------------------

empty=$(
  printf '{}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "empty tool_input exits 0" 0 "$empty"

# --- 8. Degraded mode without jq: fail-closed -------------------------------------
# Sandbox PATH containing everything the guard needs except jq. Symlinking works
# on Linux CI; on Windows/MSYS the linked bash cannot load its DLLs, so the
# sandbox is verified functional first and the cases are skipped when it isn't.

NOJQ_DIR="$(mktemp -d)"
trap 'rm -rf "$NOJQ_DIR"' EXIT
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
  assert_exit "no jq: benign payload passes" 0 "$(nojq_exit "git status")"
  assert_exit "no jq: ack prefix does NOT bypass (unverifiable)" 2 "$(nojq_exit "CLEAN_GUARD_ACK=1 git clean -fdx")"
  assert_exit "no jq: PowerShell ack does NOT bypass (unverifiable)" 2 "$(nojq_exit "$ps_ack Remove-Item -Recurse -Force obj")"
  reason=$(printf '{"tool_input":{"command":"git clean -fdx"}}' | PATH="$NOJQ_DIR" "$NOJQ_DIR/bash" "$SCRIPT" 2>&1 >/dev/null)
  assert_contains "no jq: block reason names degraded mode" "$reason" "degraded mode: jq not found"
else
  skip_case "degraded-mode cases: PATH sandbox not functional on this platform"
fi

# --- Final report -----------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1

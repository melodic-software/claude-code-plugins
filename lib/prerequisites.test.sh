#!/usr/bin/env bash
# Owns lib/prerequisites.test.mjs for the plugin test lane, then tests the sh and
# pwsh stubs: with node absent each prints one fixed line and exits 1; with node
# present each hands its arguments and exit code to prerequisites.mjs.
# scripts/run-outside-node-suites.sh treats a sibling .test.sh as the runner.
# test-scope: plugins/*/prerequisites.json plugins/*/.claude-plugin/plugin.json
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node --test "$LIB/prerequisites.test.mjs" || exit 1

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
EMPTY="$WORK/empty-path"
mkdir -p "$EMPTY"
EXPECTED='prerequisites: node was not found on PATH, so no prerequisite was checked. Install Node.js from https://nodejs.org/en/download, then run this check again.'
SH="$(command -v sh)"

out="$(PATH="$EMPTY" "$SH" "$LIB/prerequisites.sh" check "$WORK")"
rc=$?
if [[ "$rc" -eq 1 && "$out" == "$EXPECTED" ]]; then
  pass "sh stub: node absent prints the fixed line and exits 1"
else
  fail "sh stub: node absent gave rc=$rc out=$out"
fi

"$SH" "$LIB/prerequisites.sh" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "sh stub: node present passes the checker's usage exit through"
else
  fail "sh stub: node present gave rc=$rc, want 2"
fi

out="$("$SH" "$LIB/prerequisites.sh" check "$WORK")"
rc=$?
if [[ "$rc" -eq 0 && "$out" == *"declares no external dependency"* ]]; then
  pass "sh stub: node present passes the arguments through"
else
  fail "sh stub: node present gave rc=$rc out=$out"
fi

if PWSH="$(command -v pwsh)"; then
  out="$(PATH="$EMPTY" "$PWSH" -NoProfile -NonInteractive -File "$LIB/prerequisites.ps1" check "$WORK")"
  rc=$?
  out="${out%$'\r'}"
  if [[ "$rc" -eq 1 && "$out" == "$EXPECTED" ]]; then
    pass "pwsh stub: node absent prints the fixed line and exits 1"
  else
    fail "pwsh stub: node absent gave rc=$rc out=$out"
  fi
  out="$("$PWSH" -NoProfile -NonInteractive -File "$LIB/prerequisites.ps1" check "$WORK")"
  rc=$?
  if [[ "$rc" -eq 0 && "$out" == *"declares no external dependency"* ]]; then
    pass "pwsh stub: node present passes the arguments and exit code through"
  else
    fail "pwsh stub: node present gave rc=$rc out=$out"
  fi
else
  printf 'NOTE: pwsh is not on PATH; the pwsh stub cases did not run.\n'
fi

# node-notice: the SessionStart mode that must work with node absent. The stub PATH
# carries the coreutils the sh stub calls and no node.
TOOLS="$WORK/tools-path"
mkdir -p "$TOOLS" "$WORK/tmp" "$WORK/tmp-ps"
for t in sed tr find mkdir cat rm; do ln -s "$(command -v "$t")" "$TOOLS/$t"; done
notice_sh() { # <session-json> <args...>
  local payload="$1"
  shift
  printf '%s' "$payload" | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$SH" "$LIB/prerequisites.sh" node-notice "$@"
}
notice_shape() { # reads a notice on stdin; prints ok when it is exactly the user-channel line for <plugin>
  # Only the user can install node; a model copy would only relay "tell the user".
  node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));const p=process.argv[1];const want=p+": node is not on PATH, so hooks that launch through node (this plugin'"'"'s and others'"'"') do not run. Install Node.js (https://nodejs.org/en/download), restart Claude Code, then run /"+p+":check.";process.stdout.write(Object.keys(j).join()==="systemMessage"&&j.systemMessage===want?"ok":"bad")' "$1"
}
s1='{"session_id":"sess-1","hook_event_name":"SessionStart"}'

out="$(notice_sh "$s1" /bash-format:check)"
if [[ "$(printf '%s' "$out" | notice_shape bash-format)" == ok ]]; then
  pass "sh node-notice: node absent prints one SessionStart notice to the user naming the check skill"
else
  fail "sh node-notice: node absent gave $out"
fi
out="$(notice_sh "$s1" /guardrails:check)"
if [[ -z "$out" ]]; then
  pass "sh node-notice: a second plugin in the same session stays silent"
else
  fail "sh node-notice: second plugin printed $out"
fi
out="$(notice_sh '{"session_id":"sess-2"}' /guardrails:check)"
if [[ "$(printf '%s' "$out" | notice_shape guardrails)" == ok ]]; then
  pass "sh node-notice: a new session gets its own notice"
else
  fail "sh node-notice: new session gave $out"
fi
out="$(notice_sh '{"session_id":"sess-3"}' /bash-format:check BASH_FORMAT_ENABLED)"
if [[ "$out" == *'node is not on PATH'* ]]; then
  pass "sh node-notice: an unset kill switch leaves the notice on"
else
  fail "sh node-notice: unset kill switch gave $out"
fi
out="$(CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=false notice_sh '{"session_id":"sess-4"}' /bash-format:check BASH_FORMAT_ENABLED)"
if [[ -z "$out" ]]; then
  pass "sh node-notice: a plugin kill switch set to false silences the notice"
else
  fail "sh node-notice: kill switch false gave $out"
fi
a="$(notice_sh '{}' /bash-format:check)"
b="$(notice_sh '{}' /guardrails:check)"
if [[ -n "$a" && -n "$b" ]]; then
  pass "sh node-notice: with no session id every plugin still notifies"
else
  fail "sh node-notice: no session id gave a=$a b=$b"
fi
out="$(printf '%s' '{"session_id":"sess-5"}' | TMPDIR="$WORK/tmp" "$SH" "$LIB/prerequisites.sh" node-notice /bash-format:check)"
if [[ -z "$out" ]]; then
  pass "sh node-notice: node present prints nothing"
else
  fail "sh node-notice: node present gave $out"
fi

if [[ -n "${PWSH:-}" ]]; then
  notice_ps() { # <session-json> <args...>
    local payload="$1"
    shift
    printf '%s' "$payload" | PATH="$EMPTY" TMPDIR="$WORK/tmp-ps" "$PWSH" -NoProfile -NonInteractive -File "$LIB/prerequisites.ps1" node-notice "$@"
  }
  out="$(notice_ps "$s1" /bash-format:check)"
  if [[ "$(printf '%s' "$out" | notice_shape bash-format)" == ok ]]; then
    pass "pwsh node-notice: node absent prints one SessionStart notice to the user"
  else
    fail "pwsh node-notice: node absent gave $out"
  fi
  out="$(notice_ps "$s1" /guardrails:check)"
  if [[ -z "$out" ]]; then
    pass "pwsh node-notice: a second plugin in the same session stays silent"
  else
    fail "pwsh node-notice: second plugin printed $out"
  fi
  out="$(CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED=false notice_ps '{"session_id":"sess-4"}' /bash-format:check BASH_FORMAT_ENABLED)"
  if [[ -z "$out" ]]; then
    pass "pwsh node-notice: a plugin kill switch set to false silences the notice"
  else
    fail "pwsh node-notice: kill switch false gave $out"
  fi
  out="$(printf '%s' "$s1" | "$PWSH" -NoProfile -NonInteractive -File "$LIB/prerequisites.ps1" node-notice /bash-format:check)"
  if [[ -z "$out" ]]; then
    pass "pwsh node-notice: node present prints nothing"
  else
    fail "pwsh node-notice: node present gave $out"
  fi
fi

if [[ "$FAILED" -gt 0 ]]; then
  printf '%d stub case(s) failed\n' "$FAILED" >&2
  exit 1
fi

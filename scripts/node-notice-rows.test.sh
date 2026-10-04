#!/usr/bin/env bash
# Every hook plugin's SessionStart node-notice row: the fleet shape, then the row run
# for real the way each default shell would run it (bash, dash, and PowerShell on a Windows
# machine without Git Bash) with node absent.
#
# A hook that launches through node cannot report that node is missing, so each plugin
# carries one shell-form row that calls lib/prerequisites.sh and then lib/prerequisites.ps1.
# A POSIX shell (bash, or dash as /bin/sh on Debian and Ubuntu) runs the first and leaves at
# `${PPID:+exit}`, since every POSIX shell sets PPID; PowerShell finds no sh, reads
# that token as a missing drive, and runs the second. Both share one latch per session.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

MARKER='prerequisites.sh" node-notice'

# --- fleet shape ----------------------------------------------------------------
rows_checked=0
for hooks in "$ROOT"/plugins/*/hooks/hooks.json; do
  plugin="$(basename "$(dirname "$(dirname "$hooks")")")"
  mapfile -t rows < <(jq -r '[.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains("prerequisites.sh")) | .command] | .[]' "$hooks")
  if ((${#rows[@]} != 1)); then
    bad "$plugin: want exactly one node-notice SessionStart row" "found ${#rows[@]}"
    continue
  fi
  rows_checked=$((rows_checked + 1))
  row="${rows[0]}"
  [[ "$row" == *"$MARKER"* ]] || bad "$plugin: the row does not call prerequisites.sh node-notice" "$row"
  skill=check
  [[ -d "$ROOT/plugins/$plugin/skills/check-prerequisites" ]] && skill=check-prerequisites
  option=""
  if [[ "$row" =~ node-notice\ /$plugin:$skill\ ([A-Z0-9_]+)\; ]]; then option="${BASH_REMATCH[1]}"; fi
  args="node-notice /$plugin:$skill${option:+ $option}"
  want="sh \"\${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.sh\" $args; \${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File \"\${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.ps1\" $args"
  if [[ "$row" != "$want" ]]; then
    bad "$plugin: the row is not the canonical polyglot for this plugin" "$row"
    continue
  fi
  [[ -f "$ROOT/plugins/$plugin/skills/$skill/SKILL.md" ]] || bad "$plugin: the row names /$plugin:$skill but that skill does not exist"
  for lib in prerequisites.sh prerequisites.ps1 prerequisites.mjs; do
    [[ -f "$ROOT/plugins/$plugin/lib/$lib" ]] || bad "$plugin: lib/$lib is missing"
  done
  if [[ -n "$option" ]]; then
    key="$(tr '[:upper:]' '[:lower:]' <<<"$option")"
    jq -e --arg k "$key" '.userConfig[$k]' "$ROOT/plugins/$plugin/.claude-plugin/plugin.json" >/dev/null ||
      bad "$plugin: the row's kill switch $option is not a userConfig option"
  fi
done
if ((rows_checked >= 20)); then
  ok "$rows_checked hook plugins carry exactly one canonical node-notice row"
else
  bad "too few plugins carry the row" "$rows_checked"
fi

# --- the row, run with node absent ------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TOOLS="$WORK/tools"
mkdir -p "$TOOLS" "$WORK/tmp"
for t in sed tr find mkdir cat rm sh; do ln -s "$(command -v "$t")" "$TOOLS/$t"; done
printf '#!/bin/sh\n: >"%s/powershell-ran"\n' "$WORK" >"$TOOLS/powershell"
chmod +x "$TOOLS/powershell"

row_of() { jq -r '.hooks.SessionStart[].hooks[] | select((.command // "") | contains("prerequisites.sh")) | .command' "$ROOT/plugins/$1/hooks/hooks.json"; }
expand() { # <plugin> -> the row with the plugin root substituted, as Claude Code does
  local row
  row="$(row_of "$1")"
  printf '%s' "${row//\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT/plugins/$1}"
}

session='{"session_id":"row-1","hook_event_name":"SessionStart"}'
out1="$(printf '%s' "$session" | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$(command -v bash)" -c "$(expand bash-format)" 2>/dev/null)"
rc1=$?
out2="$(printf '%s' "$session" | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$(command -v bash)" -c "$(expand guardrails)" 2>/dev/null)"
rc2=$?
if ((rc1 == 0 && rc2 == 0)) && [[ "$out1" == *'"systemMessage":"bash-format: node is not on PATH'*'Run /bash-format:check to verify'* && -z "$out2" ]]; then
  ok "bash: two plugins in one session print one notice, naming the first plugin's check skill, and exit 0"
else
  bad "bash: want one notice across two plugins" "rc=$rc1/$rc2 first=$out1 second=$out2"
fi
if [[ ! -e "$WORK/powershell-ran" ]]; then
  ok "bash: the row leaves before the PowerShell half"
else
  bad "bash: the PowerShell half ran"
fi

if DASH="$(command -v dash)"; then
  out="$(printf '%s' '{"session_id":"row-dash","hook_event_name":"SessionStart"}' | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$DASH" -c "$(expand bash-format)" 2>/dev/null)"
  rc=$?
  if ((rc == 0)) && [[ "$out" == *'"systemMessage":"bash-format: node is not on PATH'* && ! -e "$WORK/powershell-ran" ]]; then
    ok "dash: the row prints the notice and leaves before the PowerShell half"
  else
    bad "dash: want the notice and no PowerShell half" "rc=$rc out=$out powershell-ran=$([[ -e "$WORK/powershell-ran" ]] && echo yes || echo no)"
  fi
else
  printf 'NOTE: dash is not on PATH; the dash case did not run.\n'
fi

if PWSH="$(command -v pwsh)"; then
  PS_TOOLS="$WORK/ps-tools"
  mkdir -p "$PS_TOOLS" "$WORK/tmp-ps"
  ln -s "$PWSH" "$PS_TOOLS/powershell"
  ps_row() { printf '%s' "$session" | PATH="$PS_TOOLS" TMPDIR="$WORK/tmp-ps" "$PWSH" -NoProfile -NonInteractive -Command "$(expand "$1")" 2>/dev/null; }
  out1="$(ps_row bash-format)"
  rc1=$?
  out2="$(ps_row guardrails)"
  if ((rc1 == 0)) && [[ "$out1" == *'"systemMessage":"bash-format: node is not on PATH'* && -z "$out2" ]]; then
    ok "powershell: with no sh, two plugins in one session print one notice and exit 0"
  else
    bad "powershell: want one notice across two plugins" "rc=$rc1 first=$out1 second=$out2"
  fi
else
  printf 'NOTE: pwsh is not on PATH; the PowerShell cases did not run.\n'
fi

test_harness::report

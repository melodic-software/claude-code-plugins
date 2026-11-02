#!/usr/bin/env bash
# The fleet's SessionStart prerequisites rows: the shape, then harness-ops' node-notice row run
# for real the way each default shell would run it (bash, dash, and PowerShell on a Windows
# machine without Git Bash) with node absent. The runtime cases run on POSIX hosts only.
#
# A hook that launches through node cannot report that node is missing, so harness-ops carries
# the fleet's one shell-form row that calls lib/prerequisites.sh and then lib/prerequisites.ps1.
# A POSIX shell (bash, or dash as /bin/sh on Debian and Ubuntu) runs the first and leaves at
# `${PPID:+exit}`, since every POSIX shell sets PPID; PowerShell finds no sh, reads
# that token as a missing drive, and runs the second. Both share one latch per session.
# Beside it, harness-ops' exec-form prerequisites-fleet.mjs row runs the probe of each enabled
# plugin that declares session_probe in its prerequisites.json, so no other plugin carries a row.
# test-scope: plugins/*/hooks/hooks.json plugins/*/.claude-plugin/plugin.json plugins/*/prerequisites.json
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# Every SessionStart source but compact (https://code.claude.com/docs/en/hooks, SessionStart
# matcher table, as of 2026-10-04): the notice and probe latches outlive a compaction, so a
# re-fire there prints nothing and only starts processes.
MATCHER='startup|resume|clear|fork'
HOOKS="$ROOT/plugins/harness-ops/hooks/hooks.json"

# --- fleet shape ----------------------------------------------------------------
carriers=()
probes=()
for hooks in "$ROOT"/plugins/*/hooks/hooks.json; do
  plugin="$(basename "$(dirname "$(dirname "$hooks")")")"
  jq -e '[.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains("prerequisites.sh"))] | length > 0' "$hooks" >/dev/null && carriers+=("$plugin")
  jq -e '[.hooks.SessionStart[]?.hooks[]? | select(((.args // [])[0] // "" | endswith("/lib/prerequisites.mjs")) and (.args[1] == "probe"))] | length > 0' "$hooks" >/dev/null && probes+=("$plugin")
done
if [[ "${carriers[*]}" == harness-ops ]]; then
  ok "only harness-ops carries a node-notice row"
else
  bad "want the node-notice row in harness-ops alone" "carriers=${carriers[*]}"
fi
if ((${#probes[@]} == 0)); then
  ok "no plugin carries its own prerequisites.mjs probe row"
else
  bad "a plugin still carries its own probe row; declare session_probe in its prerequisites.json instead" "${probes[*]}"
fi

# shellcheck disable=SC2016 # the row's ${...} placeholders are literal hooks.json text
want='sh "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.sh" node-notice /harness-ops:check; ${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.ps1" node-notice /harness-ops:check'
row="$(jq -r --arg want "$want" --arg m "$MATCHER" '[.hooks.SessionStart[] | select(.matcher == $m) | .hooks[] | select(.command == $want)] | length' "$HOOKS")"
if [[ "$row" == 1 ]]; then
  ok "harness-ops' node-notice row is the canonical polyglot under the $MATCHER matcher"
else
  bad "harness-ops: want one canonical node-notice row under $MATCHER" "found $row"
fi
fleet="$(jq -c --arg m "$MATCHER" '[.hooks.SessionStart[] | . as $g | .hooks[] | select((.args // [])[0] == "${CLAUDE_PLUGIN_ROOT}/hooks/prerequisites-fleet.mjs") | {m: $g.matcher, c: .command, n: (.args | length)}]' "$HOOKS")"
if [[ "$fleet" == "[{\"m\":\"$MATCHER\",\"c\":\"node\",\"n\":1}]" ]]; then
  ok "harness-ops carries one exec-form prerequisites-fleet.mjs row under the $MATCHER matcher"
else
  bad "harness-ops: want one exec-form prerequisites-fleet.mjs row under $MATCHER" "$fleet"
fi

declared=0
for manifest in "$ROOT"/plugins/*/prerequisites.json; do
  plugin="$(basename "$(dirname "$manifest")")"
  jq -e 'has("session_probe")' "$manifest" >/dev/null || continue
  declared=$((declared + 1))
  [[ -f "$ROOT/plugins/$plugin/lib/prerequisites.mjs" ]] || bad "$plugin: declares session_probe but carries no lib/prerequisites.mjs"
  option="$(jq -r '.session_probe.run_if_unset_or_true // ""' "$manifest")"
  if [[ -n "$option" ]]; then
    key="$(tr '[:upper:]' '[:lower:]' <<<"$option")"
    jq -e --arg k "$key" '.userConfig[$k]' "$ROOT/plugins/$plugin/.claude-plugin/plugin.json" >/dev/null ||
      bad "$plugin: session_probe's kill switch $option is not a userConfig option"
  fi
done
if ((declared >= 10)); then
  ok "$declared plugins declare session_probe, each gate a userConfig option"
else
  bad "too few plugins declare session_probe" "$declared"
fi

# --- the row, run with node absent ------------------------------------------------
node_absent_cases() {
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
  out1="$(printf '%s' "$session" | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$(command -v bash)" -c "$(expand harness-ops)" 2>/dev/null)"
  rc1=$?
  out2="$(printf '%s' "$session" | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$(command -v bash)" -c "$(expand harness-ops)" 2>/dev/null)"
  rc2=$?
  if ((rc1 == 0 && rc2 == 0)) && [[ "$out1" == *'"systemMessage":"harness-ops: node is not on PATH'*'then run /harness-ops:check."}' && -z "$out2" ]]; then
    ok "bash: the row prints one notice per session, naming /harness-ops:check, and exits 0"
  else
    bad "bash: want one notice per session" "rc=$rc1/$rc2 first=$out1 second=$out2"
  fi
  if [[ ! -e "$WORK/powershell-ran" ]]; then
    ok "bash: the row leaves before the PowerShell half"
  else
    bad "bash: the PowerShell half ran"
  fi

  if DASH="$(command -v dash)"; then
    out="$(printf '%s' '{"session_id":"row-dash","hook_event_name":"SessionStart"}' | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$DASH" -c "$(expand harness-ops)" 2>/dev/null)"
    rc=$?
    if ((rc == 0)) && [[ "$out" == *'"systemMessage":"harness-ops: node is not on PATH'* && ! -e "$WORK/powershell-ran" ]]; then
      ok "dash: the row prints the notice and leaves before the PowerShell half"
    else
      bad "dash: want the notice and no PowerShell half" "rc=$rc out=$out powershell-ran=$([[ -e "$WORK/powershell-ran" ]] && echo yes || echo no)"
    fi
  else
    printf 'NOTE: dash is not on PATH; the dash case did not run.\n'
  fi

  if PWSH="$(command -v pwsh)"; then
    # A version-manager shim (mise, asdf) dispatches on its name and refills PATH: use the real binary.
    real="$("$PWSH" -NoProfile -NonInteractive -Command '[Environment]::ProcessPath')"
    real="${real%$'\r'}"
    [[ -n "$real" ]] && PWSH="$real"
    PS_TOOLS="$WORK/ps-tools"
    mkdir -p "$PS_TOOLS" "$WORK/tmp-ps"
    ln -s "$PWSH" "$PS_TOOLS/powershell"
    ps_row() { printf '%s' "$session" | PATH="$PS_TOOLS" TMPDIR="$WORK/tmp-ps" "$PWSH" -NoProfile -NonInteractive -Command "$(expand "$1")" 2>/dev/null; }
    out1="$(ps_row harness-ops)"
    rc1=$?
    out2="$(ps_row harness-ops)"
    if ((rc1 == 0)) && [[ "$out1" == *'"systemMessage":"harness-ops: node is not on PATH'* && -z "$out2" ]]; then
      ok "powershell: with no sh, the row prints one notice per session and exits 0"
    else
      bad "powershell: want one notice per session" "rc=$rc1 first=$out1 second=$out2"
    fi
  else
    printf 'NOTE: pwsh is not on PATH; the PowerShell cases did not run.\n'
  fi
}

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN* | Windows_NT*)
  printf 'SKIP: the node-absent row cases need a stub PATH of POSIX symlinks and an extensionless powershell, which Windows cannot execute; Linux CI covers them (no coverage here, not a pass)\n'
  ;;
*) node_absent_cases ;;
esac

test_harness::report

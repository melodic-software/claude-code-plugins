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
# Beside it, harness-ops' prerequisites-fleet.mjs row runs the probe of each enabled plugin that
# declares session_probe in its prerequisites.json, so no other plugin carries a row. That row and
# every other SessionStart row that needs node run lib/node-or-skip.sh in the same polyglot shape,
# so they exit 0 silently when node is missing.
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
want='sh "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.sh" node-notice /harness-ops:prerequisites; ${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.ps1" node-notice /harness-ops:prerequisites'
row="$(jq -r --arg want "$want" --arg m "$MATCHER" '[.hooks.SessionStart[] | select(.matcher == $m) | .hooks[] | select(.command == $want)] | length' "$HOOKS")"
if [[ "$row" == 1 ]]; then
  ok "harness-ops' node-notice row is the canonical polyglot under the $MATCHER matcher"
else
  bad "harness-ops: want one canonical node-notice row under $MATCHER" "found $row"
fi
# The node-or-skip polyglot for one node argument list: each argument double-quoted, the same
# list after both stubs.
skip_row() {
  local a argv=""
  for a in "$@"; do argv+=" \"$a\""; done
  # shellcheck disable=SC2016 # literal hooks.json text
  printf 'sh "${CLAUDE_PLUGIN_ROOT}/lib/node-or-skip.sh"%s; ${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/lib/node-or-skip.ps1"%s' "$argv" "$argv"
}
# shellcheck disable=SC2016 # literal hooks.json text
want="$(skip_row '${CLAUDE_PLUGIN_ROOT}/hooks/prerequisites-fleet.mjs')"
fleet="$(jq -r --arg want "$want" --arg m "$MATCHER" '[.hooks.SessionStart[] | select(.matcher == $m) | .hooks[] | select(.command == $want and (has("args") | not))] | length' "$HOOKS")"
if [[ "$fleet" == 1 ]]; then
  ok "harness-ops carries one node-or-skip prerequisites-fleet.mjs row under the $MATCHER matcher"
else
  bad "harness-ops: want one node-or-skip prerequisites-fleet.mjs row under $MATCHER" "found $fleet"
fi

# No SessionStart row launches node in exec form: that spawn fails on every new session when
# node is missing. A row that needs node runs the node-or-skip stubs, both halves with the same
# arguments, so it exits 0 silently and the node-notice row alone tells the user.
exec_node=()
skip_bad=()
skip_rows=0
for hooks in "$ROOT"/plugins/*/hooks/hooks.json; do
  plugin="$(basename "$(dirname "$(dirname "$hooks")")")"
  jq -e '[.hooks.SessionStart[]?.hooks[]? | select(has("args") and ((.command // "") | test("(^|[/\\\\])node(\\.exe)?$")))] | length > 0' "$hooks" >/dev/null && exec_node+=("$plugin")
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    skip_rows=$((skip_rows + 1))
    first="${cmd#sh \"\$\{CLAUDE_PLUGIN_ROOT\}/lib/node-or-skip.sh\"}"
    first="${first%%; \$\{PPID:+exit\};*}"
    args=()
    # shellcheck disable=SC2016 # the quoted arguments are literal hooks.json text
    while IFS= read -r a; do args+=("$a"); done < <(grep -o '"[^"]*"' <<<"$first" | sed 's/^"//; s/"$//')
    if ((${#args[@]} == 0)) || [[ "$cmd" != "$(skip_row "${args[@]}")" ]]; then
      skip_bad+=("$plugin")
    else
      [[ -f "$ROOT/plugins/$plugin/lib/node-or-skip.sh" && -f "$ROOT/plugins/$plugin/lib/node-or-skip.ps1" ]] || skip_bad+=("$plugin(no stubs)")
    fi
  done < <(jq -r '.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains("node-or-skip")) | .command' "$hooks")
done
if ((${#exec_node[@]} == 0)); then
  ok "no plugin launches node in exec form from SessionStart"
else
  bad "SessionStart rows launch node in exec form; run them through lib/node-or-skip.sh" "${exec_node[*]}"
fi
if ((${#skip_bad[@]} == 0 && skip_rows >= 7)); then
  ok "$skip_rows node-or-skip rows are each the canonical polyglot, beside both stubs"
else
  bad "want every node-or-skip row canonical, beside both stubs" "rows=$skip_rows bad=${skip_bad[*]}"
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
  if ((rc1 == 0 && rc2 == 0)) && [[ "$out1" == *'"systemMessage":"harness-ops: node is not on PATH'*'then run /harness-ops:prerequisites."}' && -z "$out2" ]]; then
    ok "bash: the row prints one notice per session, naming /harness-ops:prerequisites, and exits 0"
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

  # --- the node-or-skip rows, node absent and present ------------------------------
  skip_plugins=()
  for hooks in "$ROOT"/plugins/*/hooks/hooks.json; do
    jq -e '[.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains("node-or-skip"))] | length > 0' "$hooks" >/dev/null &&
      skip_plugins+=("$(basename "$(dirname "$(dirname "$hooks")")")")
  done
  skip_expand() { # <plugin> -> its node-or-skip row with both placeholders substituted
    local row
    row="$(jq -r '.hooks.SessionStart[].hooks[] | select((.command // "") | contains("node-or-skip")) | .command' "$ROOT/plugins/$1/hooks/hooks.json")"
    row="${row//\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT/plugins/$1}"
    printf '%s' "${row//\$\{CLAUDE_PLUGIN_DATA\}/$WORK/data dir}"
  }
  shells=("$(command -v bash)")
  [[ -n "${DASH:-}" ]] && shells+=("$DASH")
  for shell in "${shells[@]}"; do
    failed=()
    for plugin in "${skip_plugins[@]}"; do
      rm -f "$WORK/powershell-ran"
      out="$(printf '%s' "$session" | PATH="$TOOLS" TMPDIR="$WORK/tmp" "$shell" -c "$(skip_expand "$plugin")" 2>&1)"
      rc=$?
      ((rc == 0)) && [[ -z "$out" && ! -e "$WORK/powershell-ran" ]] || failed+=("$plugin(rc=$rc out=$out)")
    done
    if ((${#failed[@]} == 0)); then
      ok "$(basename "$shell"), node absent: all ${#skip_plugins[@]} node-or-skip rows exit 0 with no output and skip the PowerShell half"
    else
      bad "$(basename "$shell"), node absent: want exit 0 and no output" "${failed[*]}"
    fi
  done

  # node present: a stub node records its argv and stdin, and exits 3.
  NODE_TOOLS="$WORK/node-tools"
  mkdir -p "$NODE_TOOLS"
  cp -P "$TOOLS"/* "$NODE_TOOLS/"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/node-args"\ncat >"%s/node-stdin"\nexit 3\n' "$WORK" "$WORK" >"$NODE_TOOLS/node"
  chmod +x "$NODE_TOOLS/node"
  want_args="$(printf '%s\n' "$ROOT/plugins/disk-hygiene/hooks/resume-notice.mjs" --marker-root "$WORK/data dir")"
  rm -f "$WORK/node-args" "$WORK/node-stdin"
  printf '%s' "$session" | PATH="$NODE_TOOLS" "$(command -v bash)" -c "$(skip_expand disk-hygiene)" >/dev/null 2>&1
  rc=$?
  if ((rc == 3)) && [[ "$(cat "$WORK/node-args" 2>/dev/null)" == "$want_args" && "$(cat "$WORK/node-stdin" 2>/dev/null)" == "$session" && ! -e "$WORK/powershell-ran" ]]; then
    ok "bash, node present: the row runs node with the row's arguments and stdin, and keeps node's exit code"
  else
    bad "bash, node present: want node's argv, stdin and exit code 3" "rc=$rc args=$(cat "$WORK/node-args" 2>/dev/null) stdin=$(cat "$WORK/node-stdin" 2>/dev/null)"
  fi

  if [[ -n "${PS_TOOLS:-}" ]]; then
    failed=()
    for plugin in "${skip_plugins[@]}"; do
      out="$(printf '%s' "$session" | PATH="$PS_TOOLS" "$PWSH" -NoProfile -NonInteractive -Command "$(skip_expand "$plugin")" 2>/dev/null)"
      rc=$?
      ((rc == 0)) && [[ -z "$out" ]] || failed+=("$plugin(rc=$rc out=$out)")
    done
    if ((${#failed[@]} == 0)); then
      ok "powershell, node absent: all ${#skip_plugins[@]} node-or-skip rows exit 0 with no output"
    else
      bad "powershell, node absent: want exit 0 and no output" "${failed[*]}"
    fi
    PS_NODE_TOOLS="$WORK/ps-node-tools"
    mkdir -p "$PS_NODE_TOOLS"
    # No sh here, as on Windows without Git Bash; the stub node's /bin/sh shebang needs only cat.
    ln -s "$PWSH" "$PS_NODE_TOOLS/powershell"
    ln -s "$NODE_TOOLS/node" "$PS_NODE_TOOLS/node"
    ln -s "$(readlink "$TOOLS/cat")" "$PS_NODE_TOOLS/cat"
    rm -f "$WORK/node-args" "$WORK/node-stdin"
    printf '%s' "$session" | PATH="$PS_NODE_TOOLS" "$PWSH" -NoProfile -NonInteractive -Command "$(skip_expand disk-hygiene)" >/dev/null 2>&1
    rc=$?
    if ((rc != 0)) && [[ "$(cat "$WORK/node-args" 2>/dev/null)" == "$want_args" && "$(cat "$WORK/node-stdin" 2>/dev/null)" == "$session" ]]; then
      ok "powershell, node present: the row runs node with the row's arguments and stdin, and fails when node fails"
    else
      bad "powershell, node present: want node's argv and stdin, and a failing exit" "rc=$rc args=$(cat "$WORK/node-args" 2>/dev/null) stdin=$(cat "$WORK/node-stdin" 2>/dev/null)"
    fi
  fi
}

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT*)
    printf 'SKIP: the node-absent row cases need a stub PATH of POSIX symlinks and an extensionless powershell, which Windows cannot execute; Linux CI covers them (no coverage here, not a pass)\n'
    ;;
  *) node_absent_cases ;;
esac

test_harness::report

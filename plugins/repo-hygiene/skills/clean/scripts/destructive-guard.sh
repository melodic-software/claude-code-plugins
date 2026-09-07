#!/usr/bin/env bash
# Session-scoped PreToolUse guard active only while the clean skill is invoked
# (registered via SKILL.md frontmatter hooks — the on-demand-hook pattern).
# Blocks destructive Bash and PowerShell commands unless the invocation is
# acknowledged with a CLEAN_GUARD_ACK=1 assignment at the very start of the
# command, which the skill body adds ONLY after the dry-run -> user-confirmation
# gate has passed. The spelling is per tool, because each one has to be a real
# assignment that takes effect for the command it prefixes:
#   Bash tool:        CLEAN_GUARD_ACK=1 <command>
#   PowerShell tool:  $env:CLEAN_GUARD_ACK=1; <command>
# Each spelling is accepted only on the tool that runs it, and only that tool.
# Any other `tool_name`, including a missing one, gets no acknowledgement path:
# the guard still blocks, it just offers nothing to unblock with. A third shell
# tool has to be added to the dispatch deliberately before it gets an ack.
#
# Usage: destructive-guard.sh [--help]   (normally invoked by the hook runner
#        with PreToolUse JSON on stdin)
# Exit codes: 0 = allow, 2 = block (stderr reason returned to Claude)

# Threat model: this is a best-effort NET, not a security boundary. It matches
# command TEXT with regexes, so obfuscation (eval, $(), base64, `bash -c`
# wrappers, aliases) bypasses it by design — the goal is to catch the common
# destructive spellings an agent might fumble and route them through the clean
# skill's confirmation gate. The durable destructive-op boundary is the consumer's own
# settings.json permissions.deny plus their git hooks, which apply independent
# of clean-session state. Known coverage gaps are accepted, not patched reactively.

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Drain stdin before any early exit so a pipefail producer never SIGPIPEs.
INPUT="$(cat)"

if [[ "${CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED:-true}" == "false" ]]; then
  exit 0
fi

# rm's recursive (-r/-R/--recursive) and force (-f/--force) flags are matched
# independently, so separated, reordered, capitalized, and long spellings are
# caught — not only the adjacent -rf cluster. git's destructive subcommands
# tolerate global options (-C <path>, -c <cfg>, --git-dir=…) between `git` and
# the subcommand. git clean keys on the force flag (-f/--force) only: -x/-X/-d
# without force are git no-ops, so blocking them (including dry-run -nx) is a
# false positive.
is_destructive() {
  local cmd="$1"
  local gopt='((-C|-c)[[:space:]]+[^[:space:]]+[[:space:]]+|--[a-zA-Z-]+=[^[:space:]]+[[:space:]]+)*'
  local force_re='[[:space:]]-[a-zA-Z]*f|[[:space:]]--force([[:space:]]|=|$)'
  if grep -qE '(^|[[:space:];&|(])rm[[:space:]]' <<<"$cmd" &&
    grep -qE '[[:space:]]-[a-zA-Z]*[rR]|[[:space:]]--recursive([[:space:]]|=|$)' <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}clean[[:space:]]" <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  grep -qE "git[[:space:]]+${gopt}reset[[:space:]]+--hard|git[[:space:]]+${gopt}checkout[[:space:]]+--[[:space:]]|git[[:space:]]+${gopt}stash[[:space:]]+(drop|clear)([[:space:]]|$)|Remove-Item[[:space:]].*-Recurse" <<<"$cmd"
}

# jq parses the hook payload. Without it the ack prefix cannot be verified, so
# the guard degrades FAIL-CLOSED: destructive patterns matched against the raw
# JSON payload block unconditionally (no ack path) until jq is installed. JSON
# escaping (e.g. tabs as \t) can hide whitespace from the patterns, so degraded
# coverage is best-effort — but a guard that cannot parse must block what it
# can see, never go silently inert (cf. #983, #532 fail-open class).
if ! command -v jq >/dev/null 2>&1; then
  # Quotes become spaces so the patterns' prefix anchors match a command at the
  # start of a JSON string value ("command":"rm -rf ..." puts a quote before rm).
  if is_destructive "${INPUT//\"/ }"; then
    {
      echo "BLOCKED by the clean skill's destructive guard (degraded mode: jq not found)."
      echo "Without jq the guard cannot verify the CLEAN_GUARD_ACK acknowledgement, so destructive commands are blocked outright."
      echo "Install jq to restore the dry-run -> user-confirmation -> CLEAN_GUARD_ACK=1 flow."
    } >&2
    exit 2
  fi
  exit 0
fi

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ -n "$CMD" ]] || exit 0
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"

# Acknowledged path: the skill's confirmation gate prefixes the command with an
# assignment. The ack is a deny-to-allow widening, so it is accepted only as
# the FIRST statement of the command, in the one spelling the executing shell
# actually evaluates as an assignment. Anywhere else (a comment, a quoted
# string, after the destructive command, a later pipeline segment) it is inert
# text and does not count. The other tool's spelling is rejected too: PowerShell
# cannot run `CLEAN_GUARD_ACK=1 <cmd>` at all, and Bash treats
# `$env:CLEAN_GUARD_ACK=1;` as a failed command lookup and runs <cmd> anyway.
#
# The dispatch is default-deny on `tool_name`: each spelling is bound to the one
# tool whose shell evaluates it, and an unrecognized, empty, or absent tool falls
# through to no ack at all. Matching on "not PowerShell" instead would hand the
# Bash spelling to every future tool by default, which is a grant nobody chose.
is_acknowledged() {
  local cmd="$1" tool="$2"
  case "$tool" in
  Bash)
    [[ "$cmd" == CLEAN_GUARD_ACK=1\ * ]]
    ;;
  PowerShell)
    # Optional leading whitespace, `$env:CLEAN_GUARD_ACK`, `=`, the value 1
    # (bare or quoted), then the `;` that ends the statement. Nothing else
    # may come before it.
    # shellcheck disable=SC2016  # literal `$env:` is the PowerShell spelling
    local ps_ack_re='^[[:space:]]*\$env:CLEAN_GUARD_ACK[[:space:]]*=[[:space:]]*(1|'"'"'1'"'"'|"1")[[:space:]]*;'
    [[ "$cmd" =~ $ps_ack_re ]]
    ;;
  *)
    return 1
    ;;
  esac
}

if is_acknowledged "$CMD" "$TOOL"; then
  exit 0
fi

if is_destructive "$CMD"; then
  # shellcheck disable=SC2016  # literal `$env:` is the PowerShell spelling
  case "$TOOL" in
  Bash) ack_form='CLEAN_GUARD_ACK=1 <command>' ;;
  PowerShell) ack_form='$env:CLEAN_GUARD_ACK=1; <command>' ;;
  *) ack_form='' ;;
  esac
  {
    echo "BLOCKED by the clean skill's destructive guard (session-scoped skill hook)."
    echo "Destructive commands during a clean run go ONLY through the skill's dry-run -> user-confirmation gate."
    if [[ -n "$ack_form" ]]; then
      echo "After the user has explicitly confirmed, re-issue with the acknowledgement prefix for this tool: $ack_form"
    else
      echo "This tool has no acknowledgement path, so there is nothing to re-issue with here. Run the confirmed command through the Bash or PowerShell tool instead."
    fi
  } >&2
  exit 2
fi

exit 0

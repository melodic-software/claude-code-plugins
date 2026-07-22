#!/usr/bin/env bash
# Session-scoped PreToolUse guard active only while the clean skill is invoked
# (registered via SKILL.md frontmatter hooks — the on-demand-hook pattern).
# Blocks destructive Bash commands unless the invocation is acknowledged with
# the CLEAN_GUARD_ACK=1 prefix, which the skill body adds ONLY after the
# dry-run -> user-confirmation gate has passed.
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
  sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
  if grep -qE '(^|[[:space:];&|(])rm[[:space:]]' <<<"$cmd" &&
    grep -qE '[[:space:]]-[a-zA-Z]*[rR]|[[:space:]]--recursive([[:space:]]|=|$)' <<<"$cmd" &&
    grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force([[:space:]]|=|$)' <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}clean[[:space:]]" <<<"$cmd" &&
    grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force([[:space:]]|=|$)' <<<"$cmd"; then
    return 0
  fi
  grep -qE "git[[:space:]]+${gopt}reset[[:space:]]+--hard|git[[:space:]]+${gopt}checkout[[:space:]]+--[[:space:]]|Remove-Item[[:space:]].*-Recurse" <<<"$cmd"
}

# jq parses the hook payload. Without it the ack prefix cannot be verified, so
# the guard degrades FAIL-CLOSED: destructive patterns matched against the raw
# JSON payload block unconditionally (no ack path) until jq is installed. JSON
# escaping (e.g. tabs as \t) can hide whitespace from the patterns, so degraded
# coverage is best-effort — but a guard that cannot parse must block what it
# can see, never go silently inert (cf. #983, #532 fail-open class).
if ! command -v jq >/dev/null 2>&1; then
  if is_destructive "$INPUT"; then
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

# Acknowledged path: the skill's confirmation gate prefixes the command.
if [[ "$CMD" == CLEAN_GUARD_ACK=1\ * ]]; then
  exit 0
fi

if is_destructive "$CMD"; then
  {
    echo "BLOCKED by the clean skill's destructive guard (session-scoped skill hook)."
    echo "Destructive commands during a clean run go ONLY through the skill's dry-run -> user-confirmation gate."
    echo "After the user has explicitly confirmed, re-issue with the acknowledgement prefix: CLEAN_GUARD_ACK=1 <command>"
  } >&2
  exit 2
fi

exit 0

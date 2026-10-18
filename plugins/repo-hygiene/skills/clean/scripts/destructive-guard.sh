#!/usr/bin/env bash
# Session-scoped PreToolUse guard registered via SKILL.md frontmatter hooks;
# a run-open marker scopes it to a clean run.
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
# command words, so obfuscation (eval, $(), base64, a `bash -c` stacked behind
# sudo, aliases) bypasses it by design — the goal is to catch the common
# destructive spellings an agent might fumble and route them through the clean
# skill's confirmation gate. The durable destructive-op boundary is the consumer's own
# settings.json permissions.deny plus their git hooks, which apply independent
# of clean-session state. Coverage is whatever is_destructive() and
# argv_destructive() list.
#
# Lifetime. Decision: a run-open marker scopes the guard, so the guard does not
# depend on when the host ends skill hooks. The marker is per session,
# <CLAUDE_PLUGIN_DATA>/clean-run/<session_id>.open, which clean-run-marker.sh
# writes when a mutating tier starts (never for scan or
# scan-batch) and removes when the run reaches its final outcome. With no marker
# for the hook input's session_id the guard allows the command. A marker idle for
# RUN_MARKER_IDLE_SECONDS (lib/run-marker.sh) is deleted and the command allowed;
# every gated call refreshes a live marker. An unresolved CLAUDE_PLUGIN_DATA or a
# missing or unusable session_id keeps the guard armed (fail closed), and so does
# the no-jq mode, which cannot read the session_id. The marker cases are in
# destructive-guard.test.sh. Not verified in this change: that CLAUDE_PLUGIN_DATA
# reaches a skill-frontmatter hook process.
# Upstream lifetime of skill-frontmatter hooks: read it live at
# https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents (anchor not
# fetched in this change; confirm it at the next recheck). As of 2026-10-18.
# Recheck: the hooks page changes how skill hooks end, or the first live run
# shows the guard armed with no marker.
#
# Precision. On the Bash tool is_destructive_bash() runs argv_destructive() over
# each segment's argv from hook::bash_parse_segments, so destructive text inside
# one quoted argument (a `gh issue comment --body '... git branch -D ...'`) is a
# single inert word and does not match. The PowerShell tool and the other tools
# keep raw-string matching in is_destructive().
#
# Branch deletion. Claim: as of 2026-09-29 this net matches bare
# `git branch -D`/`-d`/`--delete`, and `git push --delete`, `push -d` and
# `git push origin :ref` (also `+:ref`). A push with --dry-run/-n is a preview and is allowed.
# The CLEAN_GUARD_ACK path lifts these blocks like every other, and the
# ack-prefixed spelling is the documented way to run a bare `git branch -D`
# during a clean session. Spellings the patterns do not parse (a global option
# with a separate value, an alias) are not blocked. Local deletion through
# git-branch-delete.sh runs `git update-ref -d`, so the confirmed path does not
# go through these patterns. Basis: is_destructive() below and the branch and
# push block cases in destructive-guard.test.sh. Recheck: is_destructive()
# changes.
#
# Apply scripts and forced worktree removal. Claim: as of 2026-09-29 the guard
# matches the seven mutating scripts of the clean skill (clean-caches,
# clean-build, git-prune, git-tree-reset, git-tree-reset-batch, remove-path,
# clean-batch) in their --apply spelling, and `git worktree remove` with a
# force flag. A dry-run of those scripts is allowed so the confirmation gate can
# still run, and the ack prefix lifts either block after the gate. Basis:
# is_destructive() below and section 2e of destructive-guard.test.sh. Recheck:
# is_destructive() changes.

set -uo pipefail

# Builtins only: the no-jq test runs this script with a PATH that lacks dirname.
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=lib/run-marker.sh
source "$SCRIPT_DIR/lib/run-marker.sh"

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
# tolerate global options (-C <path>, -c <cfg>, --git-dir=…, flag-only ones such
# as --no-pager) between `git` and the subcommand. git clean keys on the force flag (-f/--force) only: -x/-X/-d
# without force are git no-ops, so blocking them (including dry-run -nx) is a
# false positive.
is_destructive() {
  local cmd="$1"
  local gopt='((-C|-c)[[:space:]]+[^[:space:]]+[[:space:]]+|--[a-zA-Z-]+=[^[:space:]]+[[:space:]]+|(-[pP]|--[a-zA-Z-]+)[[:space:]]+)*'
  local force_re='[[:space:]]-[a-zA-Z]*f|[[:space:]]--force([^[:alnum:]_-]|$)'
  if grep -qE '(^|[[:space:];&|(])rm[[:space:]]' <<<"$cmd" &&
    grep -qE '[[:space:]]-[a-zA-Z]*[rR]|[[:space:]]--recursive([[:space:]]|=|$)' <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}clean[[:space:]]" <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  # Basename plus --apply, so a path prefix and a dry-run do not both fire.
  # git-tree-reset-batch is its own alternative: git-tree-reset.sh does not
  # match the batch script, because `.sh` has to follow the name.
  if grep -qE '(^|[[:space:][:punct:]])(clean-caches|clean-build|git-prune|git-tree-reset-batch|git-tree-reset|remove-path|clean-batch)\.sh([^[:alnum:]_.-]|$)' <<<"$cmd" &&
    grep -qE '(^|[^[:alnum:]_-])--apply([^[:alnum:]_-]|$)' <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}worktree[[:space:]]+remove[[:space:]]" <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  # Branch deletion: a -d/-D short-flag cluster or --delete after `branch`, in the
  # same statement (a `;`, `&` or `|` ends it, so `xargs -d` after a pipe is not read).
  if grep -qE "git[[:space:]]+${gopt}branch[[:space:]]([^;&|]*[[:space:]])?['\"]?(--delete|-[a-zA-Z]*[dD])" <<<"$cmd"; then
    return 0
  fi
  # Remote deletion: `push --delete`, a -d cluster, or a `:ref` or `+:ref` refspec.
  # A dry-run (--dry-run, or an -n cluster with no -o push option) in the same push
  # statement is a preview and stays allowed.
  local push
  while IFS= read -r push; do
    if grep -qE "[[:space:]](['\"]?(--delete|-[a-np-zA-Z]*d)|['\"]?[+]?['\"]?:[^[:space:]'\"])" <<<"$push" &&
      ! grep -qE '[[:space:]](--dry-run|-[a-np-zA-Z]*n[a-np-zA-Z]*)([[:space:]]|$)' <<<"$push"; then
      return 0
    fi
  done < <(grep -oE "git[[:space:]]+${gopt}push[[:space:]][^;&|]*" <<<"$cmd")
  grep -qE "git[[:space:]]+${gopt}reset[[:space:]]+--hard|git[[:space:]]+${gopt}checkout[[:space:]]+--[[:space:]]|git[[:space:]]+${gopt}stash[[:space:]]+(drop|clear)([[:space:]]|$)|Remove-Item[[:space:]].*-Recurse" <<<"$cmd"
}

# argv_destructive <word>... : the same coverage as is_destructive(), over one
# parsed segment's argv. Every test is on a whole word, so destructive text that
# sits inside one quoted argument never matches. Returns 0 when destructive.
argv_destructive() {
  local -a w=("$@")
  local n=${#w[@]} i k j sub word base script=0 apply=0
  local -a rest
  local recursive force dry del
  for ((i = 0; i < n; i++)); do
    word="${w[i]}"
    base="${word##*/}"
    [[ "$word" == "--apply" ]] && apply=1
    case "$base" in
    clean-caches.sh | clean-build.sh | git-prune.sh | git-tree-reset-batch.sh | git-tree-reset.sh | remove-path.sh | clean-batch.sh)
      script=1
      ;;
    rm)
      recursive=0 force=0
      for ((j = i + 1; j < n; j++)); do
        [[ "${w[j]}" =~ ^-[a-zA-Z]*[rR] || "${w[j]}" =~ ^--recursive(=.*)?$ ]] && recursive=1
        [[ "${w[j]}" =~ ^-[a-zA-Z]*f || "${w[j]}" == --force ]] && force=1
      done
      ((recursive && force)) && return 0
      ;;
    Remove-Item)
      for ((j = i + 1; j < n; j++)); do
        [[ "${w[j]}" == -Recurse* ]] && return 0
      done
      ;;
    git)
      # Skip git's global options, the way the raw pattern's gopt does.
      k=$((i + 1))
      while ((k < n)); do
        case "${w[k]}" in
        -C | -c) k=$((k + 2)) ;;
        -p | -P | --*) k=$((k + 1)) ;;
        *) break ;;
        esac
      done
      sub="${w[k]:-}"
      rest=("${w[@]:k+1}")
      force=0
      for word in "${rest[@]}"; do
        [[ "$word" =~ ^-[a-zA-Z]*f || "$word" == --force ]] && force=1
      done
      case "$sub" in
      clean)
        ((force)) && return 0
        ;;
      worktree)
        [[ "${rest[0]:-}" == remove ]] && ((force)) && return 0
        ;;
      branch)
        for word in "${rest[@]}"; do
          [[ "$word" =~ ^-[a-zA-Z]*[dD] || "$word" =~ ^--delete ]] && return 0
        done
        ;;
      push)
        # A dry-run (--dry-run, or an -n cluster with no -o push option) is a preview.
        del=0 dry=0
        for word in "${rest[@]}"; do
          [[ "$word" =~ ^--delete || "$word" =~ ^-[a-np-zA-Z]*d || "$word" =~ ^[+]?:. ]] && del=1
          [[ "$word" == --dry-run || "$word" =~ ^-[a-np-zA-Z]*n[a-np-zA-Z]*$ ]] && dry=1
        done
        ((del && !dry)) && return 0
        ;;
      reset)
        [[ "${rest[0]:-}" == --hard ]] && return 0
        ;;
      checkout)
        [[ "${rest[0]:-}" == -- ]] && return 0
        ;;
      stash)
        [[ "${rest[0]:-}" == drop || "${rest[0]:-}" == clear ]] && return 0
        ;;
      *) ;;
      esac
      ;;
    *) ;;
    esac
  done
  ((script && apply)) && return 0
  return 1
}

ARGV_HIT=0
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
argv_segment() {
  ((ARGV_HIT)) && return 0
  # `bash -c '<cmd>'` and kin: the operand is a command line, parsed in turn.
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" argv_segment
    return 0
  fi
  argv_destructive "$@" && ARGV_HIT=1
  return 0
}

# is_destructive_bash <command> : is_destructive() for the Bash tool, over parsed
# segments instead of the raw string. Needs hook-utils.sh to be sourced.
is_destructive_bash() {
  ARGV_HIT=0
  hook::bash_parse_segments "$1" argv_segment
  ((ARGV_HIT))
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
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"

# Run-open marker (see Lifetime above). No live marker for this session means no
# clean run is open, so the guard stays out of the way. When the marker path
# cannot be resolved, the guard stays armed.
if run_marker_path_to MARKER_FILE "${CLAUDE_PLUGIN_DATA:-}" "$SESSION"; then
  run_marker_state_to MARKER_STATE "$MARKER_FILE"
  case "$MARKER_STATE" in
  absent) exit 0 ;;
  stale)
    rm -f "$MARKER_FILE"
    exit 0
    ;;
  *) run_marker_write "$MARKER_FILE" ;;
  esac
fi

# shellcheck source=hook-utils.sh
source "$SCRIPT_DIR/hook-utils.sh"

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

DESTRUCTIVE=0
if [[ "$TOOL" == Bash ]]; then
  is_destructive_bash "$CMD" && DESTRUCTIVE=1
else
  is_destructive "$CMD" && DESTRUCTIVE=1
fi
if ((DESTRUCTIVE)); then
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

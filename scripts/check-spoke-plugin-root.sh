#!/usr/bin/env bash
# Check that no skill spoke names a bundled path through ${CLAUDE_PLUGIN_ROOT}.
#
#   scripts/check-spoke-plugin-root.sh          discover: list every offender
#   scripts/check-spoke-plugin-root.sh --check  same, explicit form matching the
#                                               sibling gates (exit 1 on any offender)
#
# The rule: a file under plugins/*/skills/*/{context,reference,references}/
# (recursive) that contains the literal ${CLAUDE_PLUGIN_ROOT} is an offender
# unless scripts/spoke-plugin-root-baseline.txt lists it as `<path> <count>` and
# the file holds exactly <count> occurrences. A count above the baseline is a
# new hit; a count below it, or a file that is gone or no longer holds the
# token, is stale. Either way the entry must be updated or removed, so the
# baseline only shrinks.
#
# WHY. The Read tool substitutes no variables. A spoke is read, not executed, so
# a ${CLAUDE_PLUGIN_ROOT}/skills/... path in it reaches the model verbatim and
# resolves against nothing. SKILL.md is expanded by the harness, so it renders
# <skill-dir> from ${CLAUDE_SKILL_DIR} and its spokes cite <skill-dir>/scripts/...
# (plugins/claude-memory is the working pattern).
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one finding per offending file on stderr, the clean-run statement
# on stdout. Exit: 0 clean, 1 any offender, 2 environment or usage (bad
# argument, unreadable baseline, malformed entry, failed search).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

BASELINE="${SPOKE_PLUGIN_ROOT_BASELINE:-scripts/spoke-plugin-root-baseline.txt}"
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
baseline=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case
read_list::into baseline "$BASELINE" --comments inline || exit 2

ENTRY_RE='^(plugins/[^/]+/skills/[^/]+/(context|reference|references)/.+) ([1-9][0-9]*)$'
declare -A listed=()
for entry in ${baseline+"${baseline[@]}"}; do
  if [[ ! "$entry" =~ $ENTRY_RE ]]; then
    printf 'check-spoke-plugin-root: %s: "%s" is not "<spoke path> <count>" (plugins/<plugin>/skills/<skill>/{context,reference,references}/... <positive integer>)\n' \
      "$BASELINE" "$entry" >&2
    exit 2
  fi
  listed["${BASH_REMATCH[1]}"]="${BASH_REMATCH[3]}"
done

shopt -s nullglob
dirs=(plugins/*/skills/*/context plugins/*/skills/*/reference plugins/*/skills/*/references)
shopt -u nullglob

declare -A hits=()
if ((${#dirs[@]} > 0)); then
  rc=0
  # shellcheck disable=SC2016  # the token is literal text, never expanded
  found="$(LC_ALL=C grep -rIoHF -- '${CLAUDE_PLUGIN_ROOT}' "${dirs[@]}")" || rc=$?
  if ((rc > 1)); then
    printf 'check-spoke-plugin-root: grep failed (rc=%d) while searching the spokes\n' "$rc" >&2
    exit 2
  fi
  # -o -H prints one `<file>:<token>` line per occurrence.
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    f="${line%:*}"
    hits["$f"]=$((${hits["$f"]:-0} + 1))
  done <<<"$found"
fi

offenders=()
for f in "${!hits[@]}"; do
  n="${hits[$f]}"
  if [[ -z "${listed[$f]:-}" ]]; then
    # shellcheck disable=SC2016  # the token is literal text in the message
    offenders+=("$f: contains \${CLAUDE_PLUGIN_ROOT}; cite <skill-dir>/... and render <skill-dir> in SKILL.md, or list the file in $BASELINE")
  elif ((n > listed[$f])); then
    # shellcheck disable=SC2016  # the token is literal text in the message
    offenders+=("$f: has $n occurrence(s) of \${CLAUDE_PLUGIN_ROOT}, $BASELINE allows ${listed[$f]}; cite <skill-dir>/... for the new ones")
  elif ((n < listed[$f])); then
    offenders+=("$f: has $n occurrence(s), $BASELINE lists ${listed[$f]}; lower the count to $n")
  fi
done
for f in "${!listed[@]}"; do
  [[ -z "${hits[$f]:-}" ]] || continue
  if [[ -f "$f" ]]; then
    offenders+=("$f: $BASELINE lists it, but it no longer contains the token; remove the entry")
  else
    offenders+=("$f: $BASELINE lists it, but the file does not exist; remove the entry")
  fi
done

if ((${#offenders[@]} == 0)); then
  printf 'check-spoke-plugin-root: no unbaselined skill spoke names a path through the plugin-root token (%d baselined).\n' \
    "${#listed[@]}"
  exit 0
fi

printf '%s\n' "${offenders[@]}" | LC_ALL=C sort -u >&2
printf 'check-spoke-plugin-root: %d offender(s); see the header of %s for the fix pattern.\n' \
  "${#offenders[@]}" "scripts/${0##*/}" >&2
exit 1

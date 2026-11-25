#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 2

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

ENTRY_RE='^(plugins/[^/]+/skills/[^/]+/(context|reference|references|actions)/.+) ([1-9][0-9]*)$'
declare -A listed=()
for entry in ${baseline+"${baseline[@]}"}; do
  if [[ ! "$entry" =~ $ENTRY_RE ]]; then
    printf 'check-spoke-plugin-root: %s: "%s" is not "<spoke path> <count>" (plugins/<plugin>/skills/<skill>/{context,reference,references,actions}/... <positive integer>)\n' \
      "$BASELINE" "$entry" >&2
    exit 2
  fi
  listed["${BASH_REMATCH[1]}"]="${BASH_REMATCH[3]}"
done

shopt -s nullglob
dirs=(plugins/*/skills/*/context plugins/*/skills/*/reference plugins/*/skills/*/references plugins/*/skills/*/actions)
shopt -u nullglob

declare -A hits=()
if ((${#dirs[@]} > 0)); then
  rc=0
  # shellcheck disable=SC2016  # the tokens are literal text, never expanded
  found="$(LC_ALL=C grep -rIoHF -e '${CLAUDE_PLUGIN_ROOT}' -e '${CLAUDE_SKILL_DIR}' -- "${dirs[@]}")" || rc=$?
  if ((rc > 1)); then
    printf 'check-spoke-plugin-root: grep failed (rc=%d) while searching the spokes\n' "$rc" >&2
    exit 2
  fi
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
    offenders+=("$f: contains \${CLAUDE_PLUGIN_ROOT} or \${CLAUDE_SKILL_DIR}; cite <skill-dir>/... and render <skill-dir> in SKILL.md, or list the file in $BASELINE")
  elif ((n > listed[$f])); then
    offenders+=("$f: has $n occurrence(s) of \${CLAUDE_PLUGIN_ROOT} or \${CLAUDE_SKILL_DIR}, $BASELINE allows ${listed[$f]}; cite <skill-dir>/... for the new ones")
  elif ((n < listed[$f])); then
    offenders+=("$f: has $n occurrence(s), $BASELINE lists ${listed[$f]}; lower the count to $n")
  fi
done
for f in "${!listed[@]}"; do
  [[ -z "${hits[$f]:-}" ]] || continue
  if [[ -f "$f" ]]; then
    offenders+=("$f: $BASELINE lists it, but it no longer contains either token; remove the entry")
  else
    offenders+=("$f: $BASELINE lists it, but the file does not exist; remove the entry")
  fi
done

if ((${#offenders[@]} == 0)); then
  # shellcheck disable=SC2016  # the tokens are literal text in the message
  printf 'check-spoke-plugin-root: no unbaselined skill spoke names a path through ${CLAUDE_PLUGIN_ROOT} or ${CLAUDE_SKILL_DIR} (%d baselined).\n' \
    "${#listed[@]}"
  exit 0
fi

printf '%s\n' "${offenders[@]}" | LC_ALL=C sort -u >&2
printf 'check-spoke-plugin-root: %d offender(s); the Read tool expands no variables, so cite the path as <skill-dir>/... (SKILL.md renders <skill-dir>), or update a stale scripts/spoke-plugin-root-baseline.txt entry.\n' \
  "${#offenders[@]}" >&2
exit 1

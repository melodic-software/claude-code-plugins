# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/dependabot-entry.sh is sourced-only\n' >&2
  exit 2
fi

dependabot_entry::deps() {
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ Updates\ \`([^\`]+)\`\ from\ ([^[:space:]]+)\ to\ ([^[:space:]]+) ]]; then
      printf '%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    fi
  done | sort -u
}

dependabot_entry::item() {
  local title="$1" pr="$2" bundle="$3" pkg from to ref=""
  title="${title#build(deps): }"
  title="${title#chore(deps): }"
  [[ -z "$pr" ]] || ref=" (#${pr})"
  printf -- '- **%s**%s.\n' "$title" "$ref"
  while IFS=$'\t' read -r pkg from to; do
    [[ -n "${pkg:-}" ]] || continue
    # shellcheck disable=SC2016  # the backticks are Markdown
    printf '  - `%s` %s→%s\n' "$pkg" "$from" "$to"
  done
  if [[ "$bundle" == 1 ]]; then
    printf '  Committed bundle or dist artifact changed with this update.\n'
  fi
}

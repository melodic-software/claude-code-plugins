# shellcheck shell=bash
# The changelog entry for a Dependabot update. Sourced, never executed.
#
# scripts/dependabot-plugin-bump.sh writes it into a legacy plugin's CHANGELOG.md
# on the Dependabot pull request; scripts/dependabot-fragments.sh writes it into a
# fragment-mode plugin's changelog fragment after the pull request merges
# (ADR 0048). One renderer keeps the two entries alike.
#
#   dependabot_entry::deps            commit messages on stdin; prints one
#                                     "<package>\t<from>\t<to>" line per
#                                     "Updates `<package>` from <a> to <b>" line,
#                                     sorted and unique
#   dependabot_entry::item <title> <pr-number> <bundle>
#                                     deps lines (as printed above) on stdin;
#                                     prints the Keep a Changelog list item: the
#                                     title without its Conventional Commits
#                                     prefix, " (#<pr>)" when <pr-number> is set,
#                                     one indented line per dependency, and a
#                                     bundle note when <bundle> is 1

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

#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2
# shellcheck source=lib/dependabot-entry.sh
. "$SCRIPT_DIR/lib/dependabot-entry.sh" || exit 2

self="$(basename "$0")"
(($# <= 1)) || {
  echo "usage: $self [<ref>]" >&2
  exit 2
}
ref="${1:-HEAD}"
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! changed_files::verify_base "$ref"; then
  echo "$self: '$ref' is not a commit." >&2
  exit 2
fi

listed_at() {
  local names=() name text
  text="$(git show "$1:$CF_LIST" 2>/dev/null)" || return 1
  read_list::into_text names "$text" --comments inline || return 1
  for name in ${names[@]+"${names[@]}"}; do
    [[ "$name" == "$2" ]] && return 0
  done
  return 1
}

if ! commits="$(git rev-list --first-parent --author='^dependabot\[bot\] <49699333+dependabot\[bot\]@users\.noreply\.github\.com>$' "$ref" -- plugins/)"; then
  echo "$self: git rev-list on $ref failed." >&2
  exit 2
fi
written=() invalid=0
while IFS= read -r sha; do
  [[ -n "$sha" ]] || continue
  subject="$(git log -1 --format=%s "$sha")" || exit 2
  if [[ ! "$subject" =~ ^(.*)\ \(#([0-9]+)\)$ ]]; then
    echo "$self: skipped ${sha:0:8}: its subject names no pull request: $subject" >&2
    continue
  fi
  title="${BASH_REMATCH[1]}"
  pr="${BASH_REMATCH[2]}"
  changed="$(git diff-tree --no-commit-id --name-only -r "$sha" -- plugins/ .changes/)" || exit 2
  while IFS= read -r plugin; do
    [[ -n "$plugin" ]] || continue
    [[ -f "plugins/$plugin/.claude-plugin/plugin.json" ]] || continue
    changelog_fragments::in_mode "$plugin"
    case $? in
    0) ;;
    1) continue ;;
    *) exit 2 ;;
    esac
    # shellcheck disable=SC2310  # the non-zero return IS the answer
    listed_at "$sha" "$plugin" || continue
    grep -q "^\.changes/$plugin/" <<<"$changed" && continue
    path=".changes/$plugin/dependabot-$pr-${sha:0:8}.md"
    [[ ! -e "$path" ]] || continue
    if ! seen="$(git log -1 --format=%H "$ref" -- "$path")"; then
      echo "$self: git log on $path failed." >&2
      exit 2
    fi
    [[ -z "$seen" ]] || continue
    bundle=0
    grep -qE "^plugins/$plugin/.*(dist/|bundle)" <<<"$changed" && bundle=1
    mkdir -p ".changes/$plugin" || exit 2
    {
      printf -- '---\nbump: patch\n---\n\n### Changed\n\n'
      git log -1 --format=%B "$sha" | dependabot_entry::deps |
        dependabot_entry::item "$title" "$pr" "$bundle" | sed $'s/\xe2\x80\x94/-/g'
    } >"$path" || exit 2
    if changelog_fragments::validate "$path"; then
      written+=("$path")
    else
      rm -f "$path"
      invalid=1
    fi
  done < <(sed -n 's|^plugins/\([^/]*\)/.*|\1|p' <<<"$changed" | sort -u)
done <<<"$commits"
((${#written[@]} == 0)) || printf '%s\n' "${written[@]}"
exit "$invalid"

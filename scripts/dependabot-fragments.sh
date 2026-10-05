#!/usr/bin/env bash
# Write the changelog fragment for each fragment-mode plugin a merged Dependabot
# pull request changed (ADR 0048).
#
#   scripts/dependabot-fragments.sh [<ref>]
#
# A Dependabot pull request gets no commit for a plugin in fragment mode: a
# commit made with GITHUB_TOKEN holds every run on it at action_required
# (#5786), and check-changelog-fragments.sh --check-required exempts a pull
# request of verified Dependabot commits. This script supplies the fragment
# after the merge. .github/workflows/dependabot-fragments.yml runs it on main and
# lands its output through a pull request of its own.
#
# It walks every first-parent commit on <ref> (default HEAD) that Dependabot
# authored and that changed plugins/, and for each plugin that commit changed
# and that is in fragment mode both in the commit's own scripts/fragment-plugins.txt
# and in the working tree's, writes .changes/<plugin>/dependabot-<pr>-<sha8>.md:
# a `patch` fragment whose `### Changed` entry is the pull request title and its
# "Updates `<package>` from <a> to <b>" lines (scripts/lib/dependabot-entry.sh).
# The name is fixed per commit and plugin, so a fragment is written once: it is
# skipped when <ref>'s history ever added that path (a release deletes it, the
# history keeps it), when the working tree already holds it, or when the commit
# itself added a fragment for the plugin (a pull request from before this
# script). Nothing is lost when a release runs first: the fragment lands later
# and the next release takes it.
#
# Prints each path it wrote, one per line. Exit 0 (including nothing to write),
# 1 a fragment it wrote is invalid (it is removed), 2 usage or git failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
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
if ! git rev-parse -q --verify "$ref^{commit}" >/dev/null; then
  echo "$self: '$ref' is not a commit." >&2
  exit 2
fi

# listed_at <commit> <plugin>: 0 when the commit's own list names the plugin.
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
      # A purged CHANGELOG.md takes no em dash, and the release copies this body into it.
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

#!/usr/bin/env bash
# Turn pending changelog fragments into plugin releases (ADR 0048).
#
#   scripts/release-plugins.sh [--date YYYY-MM-DD]
#
# For each plugin with fragments under .changes/<plugin>/:
#   1. the new version is plugin.json's version raised once at the highest
#      `bump` among the fragments; a plugin whose fragments are all `none` gets
#      no new version and no CHANGELOG entry;
#   2. one `## [<new>] - <date>` entry goes above the newest version heading of
#      plugins/<plugin>/CHANGELOG.md, merging the fragments' bodies section by
#      section (Keep a Changelog order) in the order the fragments were
#      committed;
#   3. `version` changes in plugin.json only;
#   4. every fragment of the plugin, `none` included, is deleted.
# Prints one line per plugin. Every new changelog and manifest is produced in a
# temporary directory first, and the tree changes only once all of them exist.
# A changelog that already carries the version about to be written (a run cut
# short) is refused. <date> defaults to today in UTC.
#
# Fragment order comes from `git log`, so the release job needs the history of
# .changes/ and refuses a shallow clone; an uncommitted fragment sorts after
# every committed one.
#
# Exit: 0 released (or nothing pending), 2 usage, an invalid fragment, or a
# manifest or changelog this script cannot update.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2

self="$(basename "$0")"
date="$(date -u +%Y-%m-%d)"
if (($# == 2)) && [[ "$1" == --date && "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  date="$2"
elif (($# != 0)); then
  echo "usage: $self [--date YYYY-MM-DD]" >&2
  exit 2
fi
if ! jq --version >/dev/null 2>&1; then
  echo "$self: jq is required to read manifest versions." >&2
  exit 2
fi

fragments=()
if [[ -d .changes ]]; then
  mapfile -t fragments < <(find .changes -type f | LC_ALL=C sort)
fi
if ((${#fragments[@]} == 0)); then
  echo "No pending changelog fragments."
  exit 0
fi
for path in "${fragments[@]}"; do
  changelog_fragments::validate "$path" || {
    echo "$self: refusing to release while a fragment is invalid." >&2
    exit 2
  }
done

if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == true ]]; then
  echo "$self: this clone is shallow, so the order the fragments were committed in is unknown; fetch the full history (fetch-depth: 0) and run again." >&2
  exit 2
fi
if ! added_log="$(git log --reverse --diff-filter=A --name-only --format= -- .changes/)"; then
  echo "$self: git log of .changes/ failed; the fragment commit order is unknown." >&2
  exit 2
fi
declare -A order=()
i=0
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  i=$((i + 1))
  order["$path"]=$i
done <<<"$added_log"

declare -A rank=([none]=0 [patch]=1 [minor]=2 [major]=3)
declare -A plugin_fragments=() plugin_bump=()
plugins=()
for path in "${fragments[@]}"; do
  rest="${path#.changes/}"
  name="${rest%%/*}"
  bump="$(changelog_fragments::bump_of "$path")"
  if [[ -z "${plugin_bump[$name]:-}" ]]; then
    plugins+=("$name")
    plugin_bump["$name"]=none
  fi
  if ((rank[$bump] > rank[${plugin_bump[$name]}])); then
    plugin_bump["$name"]=$bump
  fi
  plugin_fragments["$name"]+="$(printf '%08d' "${order[$path]:-99999999}") $bump $path"$'\n'
done

# Pass 1: compute every new version and check every file it will touch.
declare -A old_version=() new_version=()
for name in "${plugins[@]}"; do
  [[ "${plugin_bump[$name]}" != none ]] || continue
  manifest="plugins/$name/.claude-plugin/plugin.json"
  changelog="plugins/$name/CHANGELOG.md"
  version="$(jq -r '.version // empty' "$manifest" 2>/dev/null)"
  if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "$self: $manifest version '$version' is not MAJOR.MINOR.PATCH; cannot raise it." >&2
    exit 2
  fi
  major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
  case "${plugin_bump[$name]}" in
  major) new="$((major + 1)).0.0" ;;
  minor) new="$major.$((minor + 1)).0" ;;
  *) new="$major.$minor.$((patch + 1))" ;;
  esac
  if [[ "$(grep -cE "^[[:space:]]*\"version\"[[:space:]]*:[[:space:]]*\"${version//./\\.}\"" "$manifest")" != 1 ]]; then
    echo "$self: $manifest does not carry exactly one \"version\": \"$version\" line to rewrite." >&2
    exit 2
  fi
  if [[ ! -f "$changelog" ]]; then
    echo "$self: $changelog does not exist; refusing to invent one." >&2
    exit 2
  fi
  if grep -qF -- "## [$new]" "$changelog"; then
    echo "$self: $changelog already has a '## [$new]' entry, so an earlier release run was cut short; restore the tree (git checkout -- .) and run again." >&2
    exit 2
  fi
  old_version["$name"]="$version"
  new_version["$name"]="$new"
done

# Pass 2: produce every new file under $stage. Nothing in the tree changes until
# all of them exist, so a failure here leaves the tree as it was.
stage="$(mktemp -d)" || exit 2
trap 'rm -rf "$stage"' EXIT
targets=()
staged=()
deletions=()
report=()
for name in "${plugins[@]}"; do
  mapfile -t ordered < <(printf '%s' "${plugin_fragments[$name]}" | LC_ALL=C sort)
  paths=()
  released=()
  for row in "${ordered[@]}"; do
    read -r _ bump path <<<"$row"
    paths+=("$path")
    [[ "$bump" == none ]] || released+=("$path")
  done

  if [[ "${plugin_bump[$name]}" == none ]]; then
    deletions+=("${paths[@]}")
    report+=("$name: no release; deleted ${#paths[@]} bump: none fragment(s): ${paths[*]}")
    continue
  fi

  manifest="plugins/$name/.claude-plugin/plugin.json"
  changelog="plugins/$name/CHANGELOG.md"
  old="${old_version[$name]}"
  new="${new_version[$name]}"

  for path in "${released[@]}"; do
    changelog_fragments::body "$path" && printf '\f\n'
  done | awk -v head="## [$new] - $date" -v sections="$CF_SECTIONS" '
      function flush() {
        sub(/^\n+/, "", buf); sub(/\n+$/, "", buf)
        if (cur != "" && buf != "") text[cur] = (cur in text) ? text[cur] "\n\n" buf : buf
        buf = ""
      }
      $0 == "\f" { flush(); cur = ""; next }
      /^###[ \t]/ { flush(); cur = $0; sub(/^###[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur); next }
      cur != "" { buf = buf $0 "\n" }
      END {
        flush()
        print head
        n = split(sections, s, " ")
        for (i = 1; i <= n; i++) if (s[i] in text) printf "\n### %s\n\n%s\n", s[i], text[s[i]]
      }
    ' >"$stage/$name.entry" || exit 2

  # The entry is read from a file, not passed with -v, which would expand the
  # backslash escapes a release note can carry.
  if ! awk -v ef="$stage/$name.entry" '
    BEGIN { while ((getline line < ef) > 0) entry = entry line "\n" }
    !done && /^##[ \t]+\[?[0-9]+\.[0-9]+/ { printf "%s\n", entry; done = 1 }
    { print }
    END { if (!done) printf "\n%s", entry }
  ' "$changelog" >"$stage/$name.changelog"; then
    echo "$self: could not produce the new $changelog." >&2
    exit 2
  fi

  if ! awk -v old="\"$old\"" -v new="\"$new\"" '
    !done && /^[ \t]*"version"[ \t]*:/ && (p = index($0, old)) { $0 = substr($0, 1, p - 1) new substr($0, p + length(old)); done = 1 }
    { print }
  ' "$manifest" >"$stage/$name.manifest"; then
    echo "$self: could not produce the new $manifest." >&2
    exit 2
  fi
  if [[ "$(jq -r '.version' "$stage/$name.manifest" 2>/dev/null)" != "$new" ]]; then
    echo "$self: rewriting $manifest did not leave version $new; nothing was written." >&2
    exit 2
  fi

  targets+=("$changelog" "$manifest")
  staged+=("$stage/$name.changelog" "$stage/$name.manifest")
  deletions+=("${paths[@]}")
  report+=("$name: $old -> $new (${plugin_bump[$name]}) from ${#paths[@]} fragment(s): ${paths[*]}")
done

# Pass 3: apply. Changelogs and manifests first and fragments last, so a run
# cut short here is caught by the existing-entry check above on the next run.
for i in "${!targets[@]}"; do
  if ! cat "${staged[i]}" >"${targets[i]}"; then
    echo "$self: could not write ${targets[i]}; restore the tree (git checkout -- .) before running again." >&2
    exit 2
  fi
done
rm -f "${deletions[@]}" || exit 2
printf '%s\n' "${report[@]}"
for name in "${plugins[@]}"; do
  rmdir ".changes/$name" 2>/dev/null || true
done
rmdir .changes 2>/dev/null || true

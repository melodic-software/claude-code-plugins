#!/usr/bin/env bash
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
declare -A skipped=()
for path in "${fragments[@]}"; do
  rest="${path#.changes/}"
  changelog_fragments::validate "$path"
  case $? in
  0) ;;
  1) skipped["${rest%%/*}"]=1 ;;
  *) exit 2 ;;
  esac
done
if ((${#skipped[@]} > 0)); then
  valid=()
  for path in "${fragments[@]}"; do
    rest="${path#.changes/}"
    [[ -n "${skipped[${rest%%/*}]:-}" ]] || valid+=("$path")
  done
  fragments=(${valid[@]+"${valid[@]}"})
  for name in $(printf '%s\n' "${!skipped[@]}" | LC_ALL=C sort); do
    echo "$self: skipped $name: a fragment under .changes/$name failed validation (above); its fragments stay until fixed." >&2
  done
  if ((${#fragments[@]} == 0)); then
    echo "No valid pending changelog fragments."
    exit 0
  fi
fi

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

declare -A old_version=() new_version=() manifest_of=() changelog_of=()
for name in "${plugins[@]}"; do
  [[ "${plugin_bump[$name]}" != none ]] || continue
  root="$(changelog_fragments::root_of "$name")" || exit 2
  changelog="$root/CHANGELOG.md"
  manifest=""
  if [[ "$root" == plugins/* ]]; then
    manifest="$root/.claude-plugin/plugin.json"
    version="$(jq -r '.version // empty' "$manifest" 2>/dev/null)"
  else
    version="$(git show "HEAD:$changelog" 2>/dev/null | changelog_fragments::newest_version -)"
  fi
  if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "$self: ${manifest:-$changelog} version '$version' is not MAJOR.MINOR.PATCH; cannot raise it." >&2
    exit 2
  fi
  major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
  case "${plugin_bump[$name]}" in
  major) new="$((major + 1)).0.0" ;;
  minor) new="$major.$((minor + 1)).0" ;;
  *) new="$major.$minor.$((patch + 1))" ;;
  esac
  if [[ -n "$manifest" && "$(grep -cE "^[[:space:]]*\"version\"[[:space:]]*:[[:space:]]*\"${version//./\\.}\"" "$manifest")" != 1 ]]; then
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
  manifest_of["$name"]="$manifest"
  changelog_of["$name"]="$changelog"
done

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

  manifest="${manifest_of[$name]}"
  changelog="${changelog_of[$name]}"
  old="${old_version[$name]}"
  new="${new_version[$name]}"

  for path in "${released[@]}"; do
    changelog_fragments::body "$path" && printf '\f\n'
  done | awk -v head="## [$new] - $date" -v sections="$CF_SECTIONS" '
      function endblock(   k) {
        if (blk == "") return
        k = blk; sub(/\n+$/, "", k)
        if (!isb || !((cur SUBSEP k) in seen)) { if (isb) seen[cur, k] = 1; buf = buf blk }
        blk = ""
      }
      function flush() {
        endblock()
        sub(/^\n+/, "", buf); sub(/\n+$/, "", buf)
        if (cur != "" && buf != "") text[cur] = (cur in text) ? text[cur] "\n\n" buf : buf
        buf = ""
      }
      $0 == "\f" { flush(); cur = ""; fence = 0; next }
      /^###[ \t]/ { flush(); cur = $0; sub(/^###[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur); next }
      cur != "" {
        if (!fence && $0 ~ /^- /) { endblock(); isb = 1 } else if (blk == "") isb = 0
        if ($0 ~ /^[ \t]*(```|~~~)/) fence = !fence
        blk = blk $0 "\n"
      }
      END {
        flush()
        print head
        n = split(sections, s, " ")
        for (i = 1; i <= n; i++) if (s[i] in text) printf "\n### %s\n\n%s\n", s[i], text[s[i]]
      }
    ' >"$stage/$name.entry" || exit 2

  if ! awk -v ef="$stage/$name.entry" '
    BEGIN { while ((getline line < ef) > 0) entry = entry line "\n" }
    !done && /^##[ \t]+\[?[0-9]+\.[0-9]+/ { printf "%s\n", entry; done = 1 }
    { print }
    END { if (!done) printf "\n%s", entry }
  ' "$changelog" >"$stage/$name.changelog"; then
    echo "$self: could not produce the new $changelog." >&2
    exit 2
  fi

  targets+=("$changelog")
  staged+=("$stage/$name.changelog")
  deletions+=("${paths[@]}")
  report+=("$name: $old -> $new (${plugin_bump[$name]}) from ${#paths[@]} fragment(s): ${paths[*]}")
  [[ -n "$manifest" ]] || continue

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

  targets+=("$manifest")
  staged+=("$stage/$name.manifest")
done

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

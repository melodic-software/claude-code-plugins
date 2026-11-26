#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "${CHANGELOG_PARITY_ROOT:-${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}}" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2

MIN_REPEATED_BODY=120

NO_OP_BUMPS="${CHANGELOG_NO_OP_BUMPS:-scripts/changelog-no-op-bumps.txt}"

GE_FLAGS=("--check" "--check-bump:ref" "--check-order" "--check-preserved:ref")
GE_BAD_REF_MSG="check-changelog-parity: base ref '${2-}' is not a resolvable commit."
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! gate_entry::classify "$@"; then
  case "${1:-}" in
  --check-bump | --check-preserved)
    echo "usage: $(basename "$0") $1 <base-ref>" >&2
    ;;
  *)
    echo "usage: $(basename "$0") [--check | --check-bump <base-ref> | --check-order | --check-preserved <base-ref>]" >&2
    ;;
  esac
  exit 2
fi
mode="$GE_MODE"

declare -A no_op_bump
no_op_rows=()
if [[ -f "$NO_OP_BUMPS" ]]; then
  read_list::into no_op_rows "$NO_OP_BUMPS" --comments inline || exit 2
  for row in ${no_op_rows[@]+"${no_op_rows[@]}"}; do
    no_op_bump["$row"]=1
  done
fi

manifests=(plugins/*/.claude-plugin/plugin.json)
if [[ ! -e "${manifests[0]}" ]]; then
  echo "error: no plugin manifests found under plugins/*/.claude-plugin/" >&2
  exit 2
fi

version_of() { jq -r '.version // empty' "$1" 2>/dev/null; }
version_at() { git show "$1:$2" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true; }
sans_version_at() { git show "$1:$2" 2>/dev/null | jq -cS 'del(.version)' 2>/dev/null; }

require_semver() {
  [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-].*)?$ ]] && return
  echo "check-changelog-parity: $1 carries a non-SemVer manifest version '$2'; refusing to pass without a comparable version." >&2
  exit 2
}

version_sort_key() {
  local _vsk_out="$1" IFS='.'
  if [[ ! "${2%%[+-]*}" =~ ^[0-9.]*$ ]]; then
    echo "check-changelog-parity: version '$2' has a field that is not a number; refusing to compare it." >&2
    exit 2
  fi
  # shellcheck disable=SC2086  # deliberate word-split of the dotted version on IFS
  set -- ${2%%[+-]*}
  printf -v "$_vsk_out" '%05d.%05d.%05d' "$((10#${1:-0}))" "$((10#${2:-0}))" "$((10#${3:-0}))"
}

rendered_lines() {
  awk -v keep="${2:-}" '
    {
      if (!infence && inhtml) {
        p = index($0, "-->")
        if (p == 0) next
        inhtml = 0
        rem = substr($0, p + 3)
        while ((q = index(rem, "<!--")) > 0) {
          rem = substr(rem, q + 4)
          r = index(rem, "-->")
          if (r == 0) { inhtml = 1; break }
          rem = substr(rem, r + 3)
        }
        next
      }
      # Three optional spaces rather than ` {0,3}`: mawk 1.3.3 implements no ERE
      # intervals and matches the braces literally, so the fence would stop being
      # recognized and this scanner would segment every changelog it reads
      # wrongly. Same CommonMark bound (up to three leading spaces), no interval.
      if (match($0, /^ ? ? ?`+/) || match($0, /^ ? ? ?~+/)) {
        seg = substr($0, RSTART, RLENGTH)
        sub(/^ +/, "", seg)
        mchar = substr(seg, 1, 1)
        mlen = length(seg)
        rest = substr($0, RSTART + RLENGTH)
        if (mlen >= 3) {
          if (!infence) {
            # opening fence; a backtick info string must not contain a backtick
            if (!(mchar == "`" && rest ~ /`/)) { infence = 1; fchar = mchar; flen = mlen; if (keep != "") print "\001" $0; next }
          } else if (mchar == fchar && mlen >= flen && rest ~ /^[ \t]*$/) {
            infence = 0; if (keep != "") print "\001" $0; next
          }
        }
      }
      if (infence) { if (keep != "") print "\001" $0; next }
      print
      rem = $0
      while ((q = index(rem, "<!--")) > 0) {
        rem = substr(rem, q + 4)
        r = index(rem, "-->")
        if (r == 0) { inhtml = 1; break }
        rem = substr(rem, r + 3)
      }
    }
  ' "$1"
}

changelog_versions() {
  rendered_lines "$1" |
    grep -oE '^##[[:space:]]+\[?[0-9]+\.[0-9]+(\.[0-9]+)?([+-][0-9A-Za-z][0-9A-Za-z.-]*)?\]?(\(|$|[[:space:]])' |
    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?([+-][0-9A-Za-z][0-9A-Za-z.-]*)?'
}

changelog_versions_batch() {
  local batch_mode="$1"
  shift
  (($# > 0)) || return 0
  awk -v mode="$batch_mode" -f "$SCRIPT_DIR/lib/changelog-versions-batch.awk" "$@"
}

missing_preserved_headings() {
  local merge_base="$1" changelog="$2" head_body="$3"
  local base_body missing v
  declare -A head_seen

  if ! git cat-file -e "$merge_base:$changelog" 2>/dev/null; then
    return 0
  fi
  if ! base_body="$(git show "$merge_base:$changelog")"; then
    echo "check-changelog-parity: 'git show $merge_base:$changelog' failed; refusing to pass without checking." >&2
    return 2
  fi

  mapfile -t base_versions < <(printf '%s\n' "$base_body" | changelog_versions -)
  ((${#base_versions[@]} > 0)) || return 0

  mapfile -t head_versions < <(printf '%s\n' "$head_body" | changelog_versions -)
  for v in ${head_versions[@]+"${head_versions[@]}"}; do head_seen["$v"]=1; done

  missing=""
  for v in ${base_versions[@]+"${base_versions[@]}"}; do
    [[ -n "${head_seen[$v]:-}" ]] && continue
    missing+="${missing:+$'\n'}$v"
  done
  if [[ -n "$missing" ]]; then
    printf '%s\n' "$missing"
  fi
  return 0
}

repeated_added_bodies() {
  local changelog="$1" added="$2"
  rendered_lines "$changelog" fenced | awk -v added="$added" -v min="$MIN_REPEATED_BODY" '
    function trim(s) { gsub(/^[ \t\n]+|[ \t\n]+$/, "", s); return s }
    function commit() { if (cur != "") body[cur] = trim(text) }
    /^##[ \t]/ {
      commit(); cur = ""; text = ""
      h = $0; sub(/^##[ \t]+\[?/, "", h)
      if (match(h, /^[0-9]+\.[0-9]+(\.[0-9]+)?([+-][0-9A-Za-z][0-9A-Za-z.-]*)?/)) {
        cur = substr(h, 1, RLENGTH); order[++n] = cur
      }
      next
    }
    { text = text $0 "\n" }
    END {
      commit()
      split(added, a, " ")
      for (i in a) isadded[a[i]] = 1
      for (i = 1; i <= n; i++) {
        v = order[i]
        if (!isadded[v] || length(body[v]) < min) continue
        for (j = 1; j <= n; j++)
          if (order[j] != v && body[order[j]] == body[v]) { print v, order[j]; break }
      }
    }
  '
}

if [[ "$mode" == "--check-order" ]]; then
  changelogs=(plugins/*/CHANGELOG.md docs/conventions/*/CHANGELOG.md docs/contracts/*/CHANGELOG.md)
  existing_changelogs=()
  for changelog in ${changelogs[@]+"${changelogs[@]}"}; do
    [[ -f "$changelog" ]] && existing_changelogs+=("$changelog")
  done
  misordered=0
  duplicated=0
  checked=${#existing_changelogs[@]}
  if ((checked > 0)); then
    while IFS=$'\t' read -r kind changelog a b; do
      b="${b%$'\r'}"
      a="${a%$'\r'}"
      case "$kind" in
      DUP)
        dupes="$(printf '%s\n' "$a" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
        echo "DUPLICATE CHANGELOG VERSION: $changelog lists ${dupes}more than once. Two branches almost certainly staged the same version; renumber one." >&2
        duplicated=$((duplicated + 1))
        ;;
      ORD)
        echo "MISORDERED CHANGELOG: $changelog is not newest-first — $a (below $b). A version that merged after a higher one already landed is a regression; renumber it above the entry it followed." >&2
        misordered=$((misordered + 1))
        ;;
      *) ;;
      esac
    done < <(changelog_versions_batch order "${existing_changelogs[@]}")
  fi

  if ((misordered > 0 || duplicated > 0)); then
    echo "Changelogs must read newest-first with no repeated version. Renumber against what is on the DEFAULT BRANCH, not against the base the branch was cut from." >&2
    gate_entry::finish 1
  fi
  echo "All $checked changelog(s) read newest-first with no duplicate versions."
  gate_entry::finish 0
fi

if [[ "$mode" == "--check" ]]; then
  missing=0
  ahead=0
  declare -A manifest_ver=()
  if jq_out="$(jq -r '[input_filename, (.version // "")] | @tsv' "${manifests[@]}" 2>/dev/null)"; then
    while IFS=$'\t' read -r _mf _mv; do
      _mv="${_mv%$'\r'}"
      [[ -n "$_mf" ]] && manifest_ver["$_mf"]="$_mv"
    done <<<"$jq_out"
  else
    for manifest in ${manifests[@]+"${manifests[@]}"}; do
      manifest_ver["$manifest"]="$(version_of "$manifest")"
    done
  fi
  check_changelogs=()
  for manifest in ${manifests[@]+"${manifests[@]}"}; do
    plugin_dir="${manifest%/.claude-plugin/plugin.json}"
    [[ -n "${manifest_ver[$manifest]:-}" && -f "$plugin_dir/CHANGELOG.md" ]] && check_changelogs+=("$plugin_dir/CHANGELOG.md")
  done
  declare -A newest_ver=()
  if ((${#check_changelogs[@]} > 0)); then
    while IFS=$'\t' read -r _cf _cv; do
      _cv="${_cv%$'\r'}"
      [[ -n "$_cf" && -z "${newest_ver[$_cf]:-}" ]] && newest_ver["$_cf"]="$_cv"
    done < <(changelog_versions_batch first "${check_changelogs[@]}")
  fi
  for manifest in ${manifests[@]+"${manifests[@]}"}; do
    plugin_dir="${manifest%/.claude-plugin/plugin.json}"
    name="${plugin_dir##*/}"
    version="${manifest_ver[$manifest]:-}"
    [[ -n "$version" ]] || continue
    if [[ -f "$plugin_dir/CHANGELOG.md" ]]; then
      require_semver "$name" "$version"
      newest="${newest_ver["$plugin_dir/CHANGELOG.md"]:-}"
      if [[ -n "$newest" ]]; then
        newest_key=""
        version_key=""
        version_sort_key newest_key "$newest"
        version_sort_key version_key "$version"
        if [[ "$newest_key" > "$version_key" ]]; then
          echo "CHANGELOG AHEAD OF MANIFEST: $plugin_dir/CHANGELOG.md documents $newest but $manifest carries $version." >&2
          echo "  Bump the manifest to $newest, or fold that entry into the version that actually ships." >&2
          ahead=$((ahead + 1))
        fi
      fi
      continue
    fi
    echo "MISSING CHANGELOG: $plugin_dir carries a versioned $manifest but no $plugin_dir/CHANGELOG.md." >&2
    echo "  Add $plugin_dir/CHANGELOG.md." >&2
    missing=$((missing + 1))
  done
  if ((missing > 0 || ahead > 0)); then
    ((ahead > 0)) && echo "A changelog entry must not name a version the manifest has not reached; the manifest may sit above the newest heading, never below it." >&2
    gate_entry::finish 1
  fi
  echo "Every versioned plugin has a CHANGELOG.md, and none documents a version above its manifest."
  gate_entry::finish 0
fi

base="$GE_REF"

declare -A bumped_candidate
declare -A shipped_changed
declare -A manifest_edited
declare -A consumed_fragment
declare -A added_headings
touched_changelogs=()
declare -A seen_changelog
head_commit=HEAD
if git rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 && git merge-base --is-ancestor 'HEAD^1' "$base" 2>/dev/null; then
  head_commit='HEAD^2'
fi
if ! merge_base="$(git merge-base "$base" "$head_commit")"; then
  echo "check-changelog-parity: 'git merge-base $base $head_commit' failed (no common ancestor, or history not fetched deeply enough); refusing to pass without checking." >&2
  exit 2
fi
diff_paths=()
if ! changed_files::into diff_paths "$merge_base..$head_commit" --include-deleted; then
  echo "check-changelog-parity: the diff from $merge_base to $head_commit failed; refusing to pass without checking." >&2
  exit 2
fi

head_has() {
  local listing
  if ! listing="$(git ls-tree --name-only "$head_commit" -- "$1")"; then
    echo "check-changelog-parity: 'git ls-tree $head_commit -- $1' failed; refusing to pass without checking." >&2
    exit 2
  fi
  [[ -n "$listing" ]]
}
head_show() {
  local -n head_show_out="$2"
  # shellcheck disable=SC2034  # a nameref: this assignment writes the caller's variable
  if ! head_show_out="$(git show "$head_commit:$1")"; then
    echo "check-changelog-parity: 'git show $head_commit:$1' failed; refusing to pass without checking." >&2
    exit 2
  fi
}
for path in ${diff_paths[@]+"${diff_paths[@]}"}; do
  case "$path" in
  plugins/*/.claude-plugin/plugin.json)
    rest="${path#plugins/}"
    bumped_candidate["${rest%%/*}"]=1
    if [[ "$(sans_version_at "$merge_base" "$path")" != "$(sans_version_at "$head_commit" "$path")" ]]; then
      manifest_edited["${rest%%/*}"]=1
    fi
    ;;
  plugins/*/CHANGELOG.md)
    rest="${path#plugins/}"
    if [[ "$rest" == "${rest%%/*}/CHANGELOG.md" && -z "${seen_changelog[$path]:-}" ]]; then
      seen_changelog["$path"]=1
      touched_changelogs+=("$path")
    fi
    ;;
  plugins/*/*)
    rest="${path#plugins/}"
    shipped_changed["${rest%%/*}"]=1
    ;;
  .changes/*/*)
    if ! head_has "$path"; then
      rest="${path#.changes/}"
      consumed_fragment["${rest%%/*}"]=1
    fi
    ;;
  docs/conventions/*/CHANGELOG.md | docs/contracts/*/CHANGELOG.md)
    rest="${path#docs/*/}"
    if [[ "$rest" == "${rest%%/*}/CHANGELOG.md" && -z "${seen_changelog[$path]:-}" ]]; then
      seen_changelog["$path"]=1
      touched_changelogs+=("$path")
    fi
    ;;
  *) ;;
  esac
done

if [[ "$mode" == "--check-preserved" ]]; then
  deleted=0
  compared=0
  declare -A head_seen
  for changelog in ${touched_changelogs[@]+"${touched_changelogs[@]}"}; do
    if ! base_listing="$(git ls-tree -r --name-only "$merge_base" -- "$changelog")"; then
      echo "check-changelog-parity: 'git ls-tree -r --name-only $merge_base -- $changelog' failed; refusing to pass without checking." >&2
      exit 2
    fi
    [[ -n "$base_listing" ]] || continue
    if ! base_body="$(git show "$merge_base:$changelog")"; then
      echo "check-changelog-parity: 'git show $merge_base:$changelog' failed; refusing to pass without checking." >&2
      exit 2
    fi
    mapfile -t base_versions < <(printf '%s\n' "$base_body" | changelog_versions -)
    ((${#base_versions[@]} > 0)) || continue

    head_versions=()
    changelog_at_head=""
    if head_has "$changelog"; then
      changelog_at_head=1
      head_show "$changelog" head_body
      mapfile -t head_versions < <(printf '%s\n' "$head_body" | changelog_versions -)
    elif ! head_has "${changelog%/CHANGELOG.md}"; then
      continue
    fi

    head_seen=()
    for v in ${head_versions[@]+"${head_versions[@]}"}; do head_seen["$v"]=1; done
    missing=""
    for v in ${base_versions[@]+"${base_versions[@]}"}; do
      [[ -n "${head_seen[$v]:-}" ]] && continue
      head_seen["$v"]=1
      missing="${missing}${missing:+ }$v"
    done
    compared=$((compared + ${#base_versions[@]}))

    if [[ -n "$missing" ]]; then
      echo "DELETED CHANGELOG ENTRY: $changelog documented $missing at the fork point but no longer does." >&2
      if [[ -n "$changelog_at_head" ]]; then
        echo "  A released section's heading vanished. The usual cause is a CHANGELOG merge-forward resolved by writing the new release under the PREVIOUS release's heading — absorbing it — or by RELABELING that heading to the new version; git leaves no conflict marker behind for either. Restore the heading with its own notes above the entry that replaced it." >&2
      else
        echo "  The changelog itself was deleted while its directory survived. Restore $changelog with every release note it carried at $merge_base." >&2
      fi
      echo "  Neither removal an author might intend needs a deletion. A yanked release keeps its heading, marked '## [<version>] - <date> [YANKED]' (Keep a Changelog). A note written against a version the manifest then SKIPPED keeps its heading too — say so in the section body rather than folding the notes into the release that shipped; the manifest cannot be bumped back down onto the skipped number, which --check-bump reads as a VERSION REGRESSION." >&2
      deleted=$((deleted + 1))
    fi
  done

  if ((deleted > 0)); then
    echo "A released '## [<version>]' entry may never be dropped by a change set; every heading present at the fork point must still be present at head." >&2
    gate_entry::finish 1
  fi
  echo "All ${#touched_changelogs[@]} changed changelog(s) preserve every version heading they carried at $merge_base ($compared heading(s) compared)."
  gate_entry::finish 0
fi

undocumented=0
malformed=0
preexisting=0
nonmonotonic=0
published_reuse=0
absorbed=0
repeated=0
empty_bump=0
fragment_release=0
release_pr=""
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if changelog_fragments::is_release_pr; then
  release_pr=1
fi

declare -A rename_source=()
if ! rename_listing="$(git diff --name-status -M --diff-filter=R "$merge_base" "$head_commit" -- '*CHANGELOG.md')"; then
  echo "check-changelog-parity: the rename diff from $merge_base to $head_commit failed; refusing to pass without checking." >&2
  exit 2
fi
while IFS=$'\t' read -r _ old new; do
  [[ -n "${new:-}" ]] && rename_source["$new"]="$old"
done <<<"$rename_listing"

for changelog in ${touched_changelogs[@]+"${touched_changelogs[@]}"}; do
  head_has "$changelog" || continue
  head_show "$changelog" head_body
  missing_headings="$(missing_preserved_headings "$merge_base" "$changelog" "$head_body")" ||
    exit 2
  if [[ -n "$missing_headings" ]]; then
    echo "ABSORBED CHANGELOG HEADING: $changelog lost release section heading(s) vs the fork point (a merge-forward may have fused two releases into one section):" >&2
    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      echo "  ## [$v]" >&2
    done <<<"$missing_headings"
    absorbed=$((absorbed + 1))
  fi

  base_body=""
  base_path="$changelog"
  git cat-file -e "$merge_base:$changelog" 2>/dev/null || base_path="${rename_source[$changelog]:-}"
  if [[ -n "$base_path" ]] && git cat-file -e "$merge_base:$base_path" 2>/dev/null; then
    if ! base_body="$(git show "$merge_base:$base_path")"; then
      echo "check-changelog-parity: 'git show $merge_base:$base_path' failed; refusing to pass without checking." >&2
      exit 2
    fi
  fi
  declare -A base_has=()
  for v in $(printf '%s\n' "$base_body" | changelog_versions -); do base_has["$v"]=1; done
  added_versions=""
  for v in $(printf '%s\n' "$head_body" | changelog_versions -); do
    [[ -n "${base_has[$v]:-}" ]] || added_versions+="$v "
  done
  if [[ -n "$added_versions" && "$changelog" == plugins/* ]]; then
    rest="${changelog#plugins/}"
    added_headings["${rest%%/*}"]="$added_versions"
  fi
  if [[ -n "$added_versions" && -z "$release_pr" ]] && name="$(changelog_fragments::convention_of "$changelog")"; then
    changelog_fragments::in_mode "$name"
    case $? in
    0)
      echo "FRAGMENT-MODE RELEASE: $name is in fragment mode ($CF_LIST) but this change set adds the version heading(s) ${added_versions% } to $changelog." >&2
      fragment_release=$((fragment_release + 1))
      ;;
    1) ;;
    *) exit 2 ;;
    esac
  fi
  if [[ -n "$added_versions" ]]; then
    while read -r added copied; do
      [[ -n "$added" ]] || continue
      echo "REPEATED CHANGELOG BODY: $changelog entry [$added] has the same body as [$copied]; describe what changed in this release." >&2
      repeated=$((repeated + 1))
    done < <(printf '%s\n' "$head_body" | repeated_added_bodies - "$added_versions")
  fi
done

for manifest in ${manifests[@]+"${manifests[@]}"}; do
  plugin_dir="${manifest%/.claude-plugin/plugin.json}"
  name="${plugin_dir##*/}"
  changelog="$plugin_dir/CHANGELOG.md"

  if [[ -z "$release_pr" ]]; then
    changelog_fragments::in_mode "$name"
    case $? in
    0)
      if [[ -n "${bumped_candidate[$name]:-}" ]]; then
        head_version="$(version_at "$head_commit" "$manifest")"
        fork_version="$(version_at "$merge_base" "$manifest")"
        if [[ -n "$fork_version" && "$head_version" != "$fork_version" ]]; then
          echo "FRAGMENT-MODE RELEASE: $name is in fragment mode ($CF_LIST) but this change set moves its version $fork_version -> $head_version." >&2
          fragment_release=$((fragment_release + 1))
        fi
      fi
      if [[ -n "${added_headings[$name]:-}" ]]; then
        echo "FRAGMENT-MODE RELEASE: $name is in fragment mode ($CF_LIST) but this change set adds the version heading(s) ${added_headings[$name]% } to $changelog." >&2
        fragment_release=$((fragment_release + 1))
      fi
      continue
      ;;
    1) ;;
    *) exit 2 ;;
    esac
  fi

  [[ -n "${shipped_changed[$name]:-}" || -n "${bumped_candidate[$name]:-}" ]] || continue

  base_version="$(version_at "$base" "$manifest")"
  [[ -n "$base_version" ]] || continue
  head_version="$(version_at "$head_commit" "$manifest")"
  fork_version="$(version_at "$merge_base" "$manifest")"

  if [[ -n "${shipped_changed[$name]:-}" && "$head_version" == "$fork_version" ]]; then
    if [[ -n "${bumped_candidate[$name]:-}" || "$head_version" == "$base_version" ]]; then
      echo "PUBLISHED VERSION REUSE: $name still carries $head_version while this change set modifies files under plugins/$name/ — bump the manifest and add a new '## [$head_version]' release entry instead of editing in place." >&2
      published_reuse=$((published_reuse + 1))
      continue
    fi
  fi

  [[ -n "${bumped_candidate[$name]:-}" ]] || continue

  [[ "$head_version" != "$fork_version" ]] || continue

  require_semver "$name" "$head_version"
  require_semver "$name" "$base_version"
  head_key=""
  base_key=""
  version_sort_key head_key "$head_version"
  version_sort_key base_key "$base_version"
  if [[ ! "$head_key" > "$base_key" ]]; then
    prefix=""
    [[ "${CHANGELOG_PARITY_COLLISIONS:-}" == advisory ]] && prefix="ADVISORY (the merge queue enforces this): "
    if [[ "$head_key" == "$base_key" ]]; then
      echo "${prefix}VERSION COLLISION: $name is bumped to $head_version but $base already carries $base_version — another change set claimed that number first; renumber above it." >&2
    else
      echo "${prefix}VERSION REGRESSION: $name is bumped to $head_version but $base already carries $base_version — merging would move the version BACKWARD; renumber above $base_version." >&2
    fi
    [[ -n "$prefix" ]] || nonmonotonic=$((nonmonotonic + 1))
    continue
  fi

  if [[ -z "${shipped_changed[$name]:-}" && -z "${manifest_edited[$name]:-}" && -z "${consumed_fragment[$name]:-}" && -z "${no_op_bump["$name@$head_version"]:-}" ]]; then
    echo "BUMP WITHOUT CHANGE: $name went $base_version -> $head_version but this change set touches nothing under plugins/$name/ besides plugin.json and CHANGELOG.md; ship the change with the bump, or name '$name@$head_version' in $NO_OP_BUMPS if the re-release is deliberate." >&2
    empty_bump=$((empty_bump + 1))
  fi

  heading="## [${head_version}]"
  has_heading() {
    rendered_lines - | awk -v h="$heading" '
      index($0, h) == 1 { found = 1 }
      END { exit !found }
    '
  }
  changelog_at_head=""
  head_body=""
  if head_has "$changelog"; then
    changelog_at_head=1
    head_show "$changelog" head_body
  fi
  if [[ -n "$changelog_at_head" ]] && has_heading <<<"$head_body"; then
    if git show "$base:$changelog" 2>/dev/null | has_heading; then
      echo "PRE-EXISTING CHANGELOG ENTRY: $name bumped $base_version -> $head_version but '## [$head_version]' already existed in $changelog at $base; add the release entry in this change set." >&2
      preexisting=$((preexisting + 1))
    fi
    continue
  fi

  # shellcheck disable=SC2016  # single quotes are deliberate: $ is an ERE metachar being escaped, not a shell expansion
  esc="$(printf '%s' "$head_version" | sed -E 's/[][\\.|$(){}?+*^]/\\&/g')"
  if found="$([[ -n "$changelog_at_head" ]] && grep -m1 -E "^##[[:space:]]+${esc}([[:space:]]|\$)" <<<"$head_body")"; then
    echo "CHANGELOG FORMAT: $name $head_version is documented as '${found}' but must use the bracketed Keep-a-Changelog heading '## [$head_version]'." >&2
    malformed=$((malformed + 1))
  else
    echo "UNDOCUMENTED BUMP: $name went $base_version -> $head_version but $changelog has no '## [$head_version]' entry at head." >&2
    undocumented=$((undocumented + 1))
  fi
done

if ((undocumented > 0 || malformed > 0 || preexisting > 0 || nonmonotonic > 0 || absorbed > 0 || published_reuse > 0 || repeated > 0 || empty_bump > 0 || fragment_release > 0)); then
  ((fragment_release > 0)) && echo "Only the release pull request (branch $CF_RELEASE_BRANCH) changes a fragment-mode plugin's version or CHANGELOG.md. Revert those edits and describe the change in a fragment under .changes/<plugin>/: scripts/new-changelog-fragment.sh <plugin> <major|minor|patch|none>." >&2
  ((undocumented > 0)) && echo "Add a '## [<version>]' entry for every plugin whose version changed." >&2
  ((malformed > 0)) && echo "Convert unbracketed changelog headings to the '## [<version>]' Keep-a-Changelog form." >&2
  ((preexisting > 0)) && echo "Add the bumped version's '## [<version>]' entry in this change set; it must be absent from the base changelog, not merely present at head." >&2
  ((nonmonotonic > 0)) && echo "Renumber every bumped version strictly above the base ref's CURRENT version, not the version the branch was cut from." >&2
  ((absorbed > 0)) && echo "Restore every '## [<version>]' heading that existed at the fork point; release notes must not be relabeled or absorbed into a newer section." >&2
  ((repeated > 0)) && echo "An entry added by this change set may not repeat another entry's body verbatim (bodies under $MIN_REPEATED_BODY characters are exempt)." >&2
  ((empty_bump > 0)) && echo "Bump a plugin's version only in the change set that changes a file it ships." >&2
  ((published_reuse > 0)) && echo "Bump the manifest version and add a new '## [<version>]' release entry whenever this change set modifies shipped plugin files — reusing a published version number is not allowed." >&2
  gate_entry::finish 1
fi
echo "Every plugin whose version changed vs $base has a '## [<version>]' CHANGELOG.md entry."
gate_entry::finish 0

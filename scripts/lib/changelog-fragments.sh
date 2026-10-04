# shellcheck shell=bash
# Changelog fragments (ADR 0048). Sourced, never executed; every caller runs
# from the repository root.
#
# A fragment is .changes/<plugin>/<branch-slug>-<8 hex>.md: YAML front matter
# carrying one key, `bump: major|minor|patch|none`, then a Keep a Changelog body
# of `### <Section>` blocks. A `bump: none` fragment needs only a non-empty
# reason line. scripts/release-plugins.sh turns pending fragments into a version
# bump and one CHANGELOG entry per plugin.
#
# Only plugins named in scripts/fragment-plugins.txt are in fragment mode. A
# missing list is an empty one: every plugin then keeps the per-PR bump, which is
# the stricter of the two paths.
#
#   changelog_fragments::in_mode <plugin>         0 when <plugin> is listed
#   changelog_fragments::is_release_pr            0 when CHANGELOG_HEAD_REF is
#                                                 $CF_RELEASE_BRANCH. CI sets it to
#                                                 the head branch of a pull request
#                                                 from this repository, never a fork,
#                                                 so only the release pull request,
#                                                 which release-plugins.yml writes,
#                                                 answers 0
#   changelog_fragments::bump_of <file>           print the fragment's bump; 1 and
#                                                 a reason on stdout when the front
#                                                 matter is malformed
#   changelog_fragments::validate <path>          print each finding on stderr; 1
#                                                 when there is one
#   changelog_fragments::bump_delivered <base> <plugin> <base-version> <head-version>
#                                                 the shared bump predicate: 0 when
#                                                 the version moved, or the plugin is
#                                                 listed and the diff against <base>
#                                                 adds a fragment for it whose bump
#                                                 is not none; 1 otherwise; 2 when
#                                                 git fails

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/changelog-fragments.sh is sourced-only\n' >&2
  exit 2
fi

if ! declare -F read_list::into >/dev/null 2>&1; then
  # shellcheck source=read-list.sh
  . "${BASH_SOURCE[0]%/*}/read-list.sh"
fi

CF_LIST="scripts/fragment-plugins.txt"
CF_RELEASE_BRANCH="release/plugins"
CF_SECTIONS="Added Changed Deprecated Removed Fixed Security"

declare -gA _CF_MODE=()
_CF_MODE_LOADED=""

changelog_fragments::in_mode() {
  local _cf_names=() _cf_name
  if [[ -z "$_CF_MODE_LOADED" ]]; then
    _CF_MODE_LOADED=1
    if [[ -f "$CF_LIST" ]]; then
      read_list::into _cf_names "$CF_LIST" --comments inline || return 2
      for _cf_name in ${_cf_names[@]+"${_cf_names[@]}"}; do
        _CF_MODE["$_cf_name"]=1
      done
    fi
  fi
  [[ -n "${_CF_MODE[$1]:-}" ]]
}

changelog_fragments::is_release_pr() {
  [[ "${CHANGELOG_HEAD_REF:-}" == "$CF_RELEASE_BRANCH" ]]
}

changelog_fragments::bump_of() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") { err = "front matter must open with --- on line 1"; exit } next }
    $0 == "---" { closed = 1; exit }
    /^[ \t]*$/ { next }
    /^bump:/ {
      if (bump != "") { err = "front matter sets bump twice"; exit }
      bump = $0; sub(/^bump:[ \t]*/, "", bump); sub(/[ \t]+$/, "", bump)
      next
    }
    { err = "front matter has a key other than bump: " $0; exit }
    END {
      if (err == "" && NR == 0) err = "file is empty"
      if (err == "" && !closed) err = "front matter is not closed with ---"
      if (err == "" && bump !~ /^(major|minor|patch|none)$/) err = "bump must be major, minor, patch or none, not \"" bump "\""
      if (err != "") { print err; exit 1 }
      print bump
    }
  ' "$1"
}

# The lines after the closing front matter delimiter.
changelog_fragments::body() {
  awk '{ sub(/\r$/, "") } fm == 2 { print; next } $0 == "---" { fm++ }' "$1"
}

changelog_fragments::validate() {
  local path="$1" plugin rest bump problems line
  rest="${path#.changes/}"
  plugin="${rest%%/*}"
  if [[ "$path" != .changes/* || "$rest" != "$plugin/"* || "${rest#*/}" == */* ]]; then
    echo "MISPLACED FRAGMENT: $path is not .changes/<plugin>/<name>.md." >&2
    return 1
  fi
  if [[ ! "${rest#*/}" =~ ^[a-z0-9][a-z0-9._-]*-[0-9a-f]{8}\.md$ ]]; then
    echo "FRAGMENT NAME: $path is not named <branch-slug>-<8 hex>.md; create fragments with scripts/new-changelog-fragment.sh." >&2
    return 1
  fi
  if [[ ! -f "plugins/$plugin/.claude-plugin/plugin.json" ]]; then
    echo "UNKNOWN PLUGIN: $path names '$plugin', which has no plugins/$plugin/.claude-plugin/plugin.json." >&2
    return 1
  fi
  changelog_fragments::in_mode "$plugin"
  case $? in
  0) ;;
  1)
    echo "NOT IN FRAGMENT MODE: $path is for '$plugin', which $CF_LIST does not list; bump its plugin.json and CHANGELOG.md in the pull request instead." >&2
    return 1
    ;;
  *) return 2 ;;
  esac
  if ! bump="$(changelog_fragments::bump_of "$path")"; then
    echo "FRAGMENT FRONT MATTER: $path: $bump." >&2
    return 1
  fi
  if [[ "$bump" == none ]]; then
    if ! grep -q '[^[:space:]]' < <(changelog_fragments::body "$path"); then
      echo "FRAGMENT BODY: $path has bump: none and no line saying why no release is needed." >&2
      return 1
    fi
    return 0
  fi
  problems="$(changelog_fragments::body "$path" | awk -v known="$CF_SECTIONS" '
    BEGIN { n = split(known, k, " "); for (i = 1; i <= n; i++) ok[k[i]] = 1 }
    /^###[ \t]/ {
      cur = $0; sub(/^###[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur)
      if (!(cur in ok)) print "unknown section \"### " cur "\" (use " known ")"
      if (!(cur in seen)) order[++sections] = cur
      seen[cur] = 1
      next
    }
    /^##?[ \t]/ { print "a # or ## heading would break the CHANGELOG structure: " $0; next }
    /[^ \t]/ { if (cur == "") print "text before the first ### section: " $0; else filled[cur] = 1 }
    END {
      if (sections == 0) print "no ### section"
      for (i = 1; i <= sections; i++) if (!(order[i] in filled)) print "section \"### " order[i] "\" is empty"
    }
  ')"
  if [[ -n "$problems" ]]; then
    while IFS= read -r line; do
      echo "FRAGMENT BODY: $path: $line." >&2
    done <<<"$problems"
    return 1
  fi
  return 0
}

changelog_fragments::bump_delivered() {
  local base="$1" plugin="$2" base_version="$3" head_version="$4" added path rc
  if [[ "$head_version" != "$base_version" ]]; then
    return 0
  fi
  changelog_fragments::in_mode "$plugin"
  rc=$?
  ((rc == 0)) || return "$rc"
  if ! added="$(git diff --name-only --no-renames --diff-filter=A "$base" -- ".changes/$plugin/")"; then
    echo "changelog-fragments: git diff against $base failed for .changes/$plugin/" >&2
    return 2
  fi
  while IFS= read -r path; do
    [[ -n "$path" && -f "$path" ]] || continue
    if [[ "$(changelog_fragments::bump_of "$path" 2>/dev/null)" =~ ^(major|minor|patch)$ ]]; then
      return 0
    fi
  done <<<"$added"
  return 1
}

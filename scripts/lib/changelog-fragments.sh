# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/changelog-fragments.sh is sourced-only\n' >&2
  exit 2
fi

if ! declare -F read_list::into >/dev/null 2>&1; then
  # shellcheck source=read-list.sh
  . "${BASH_SOURCE[0]%/*}/read-list.sh"
fi

CF_LIST="${CF_LIST:-scripts/fragment-plugins.txt}"
CF_RELEASE_BRANCH="release/plugins"
CF_SECTIONS="Added Changed Deprecated Removed Fixed Security"
CF_EM_DASH_LIST="scripts/em-dash-purged-paths.txt"

declare -gA _CF_MODE=()
_CF_MODE_LOADED=""
declare -ga _CF_PURGED=()
_CF_PURGED_LOADED=""

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

changelog_fragments::root_of() {
  if [[ -f "plugins/$1/.claude-plugin/plugin.json" ]]; then
    printf 'plugins/%s\n' "$1"
  elif [[ -f "docs/contracts/$1/CHANGELOG.md" ]]; then
    printf 'docs/contracts/%s\n' "$1"
  elif [[ -f "docs/conventions/$1/CHANGELOG.md" ]]; then
    printf 'docs/conventions/%s\n' "$1"
  else
    return 1
  fi
}

changelog_fragments::convention_of() {
  local rest name
  case "$1" in
  docs/contracts/*/* | docs/conventions/*/*) ;;
  *) return 1 ;;
  esac
  rest="${1#docs/*/}"
  name="${rest%%/*}"
  [[ "$(changelog_fragments::root_of "$name")" == "${1%"$rest"}$name" ]] || return 1
  printf '%s\n' "$name"
}

changelog_fragments::newest_version() {
  awk '{ sub(/\r$/, "") } match($0, /^##[ \t]+\[?[0-9]+(\.[0-9]+)+/) { v = substr($0, 1, RLENGTH); sub(/^##[ \t]+\[?/, "", v); print v; exit }' "$1"
}

changelog_fragments::em_dash_purged() {
  local changelog="$1/CHANGELOG.md" glob
  if [[ -z "$_CF_PURGED_LOADED" ]]; then
    _CF_PURGED_LOADED=1
    if [[ -f "$CF_EM_DASH_LIST" ]]; then
      read_list::into _CF_PURGED "$CF_EM_DASH_LIST" --comments inline || return 2
    fi
  fi
  for glob in ${_CF_PURGED[@]+"${_CF_PURGED[@]}"}; do
    # shellcheck disable=SC2053  # unquoted on purpose: the entry is a glob
    if [[ "$changelog" == $glob && "${changelog//[^\/]/}" == "${glob//[^\/]/}" ]]; then
      return 0
    fi
  done
  return 1
}

changelog_fragments::em_dash_lines() {
  changelog_fragments::body "$1" | LC_ALL=C grep -F $'\xe2\x80\x94' || true
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

changelog_fragments::body() {
  awk '{ sub(/\r$/, "") } fm == 2 { print; next } $0 == "---" { fm++ }' "$1"
}

changelog_fragments::validate() {
  local path="$1" plugin rest bump problems line root
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
  if ! root="$(changelog_fragments::root_of "$plugin")"; then
    echo "UNKNOWN PLUGIN: $path names '$plugin', which has no plugins/$plugin/.claude-plugin/plugin.json and no docs/contracts/$plugin/CHANGELOG.md or docs/conventions/$plugin/CHANGELOG.md." >&2
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
    { all = all $0 "\n" }
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
      # An unclosed <!--, even inside a code span, hides every CHANGELOG line after it from the parity checks.
      while ((q = index(all, "<!--")) > 0) {
        all = substr(all, q + 4)
        if ((c = index(all, "-->")) == 0) { print "<!-- is never closed with -->"; break }
        all = substr(all, c + 3)
      }
    }
  ')"
  if [[ -n "$problems" ]]; then
    while IFS= read -r line; do
      echo "FRAGMENT BODY: $path: $line." >&2
    done <<<"$problems"
    return 1
  fi
  changelog_fragments::em_dash_purged "$root"
  case $? in
  0) ;;
  1) return 0 ;;
  *) return 2 ;;
  esac
  problems="$(changelog_fragments::em_dash_lines "$path")" || return 2
  if [[ -n "$problems" ]]; then
    while IFS= read -r line; do
      echo "FRAGMENT EM DASH: $path: $line" >&2
    done <<<"$problems"
    echo "  $root/CHANGELOG.md is listed in $CF_EM_DASH_LIST and the release copies this text into it; replace each em dash, in code too, with a comma, colon, parentheses or a new sentence." >&2
    return 1
  fi
  return 0
}

changelog_fragments::bump_delivered() {
  local base="$1" plugin="$2" base_version="$3" head_version="$4" added path
  [[ "$head_version" == "$base_version" ]] || return 0
  changelog_fragments::in_mode "$plugin" || return
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

changelog_fragments::dependabot_only() {
  changelog_fragments::bot_only "$1" 'dependabot[bot]' '49699333+dependabot[bot]@users.noreply.github.com'
}

changelog_fragments::standards_sync_only() {
  changelog_fragments::bot_only "$1" 'melodic-standards-sync[bot]' '300666570+melodic-standards-sync[bot]@users.noreply.github.com'
}

# shellcheck disable=SC2034 # CF_BOT_BLOCKER is read by the sourcing script
changelog_fragments::bot_only() {
  local base="$1" login="$2" email="$3" tip=HEAD from commits sha an ae ce verified
  [[ "${CHANGELOG_PR_AUTHOR:-}" == "$login" && -n "${GITHUB_REPOSITORY:-}" ]] || return 1
  CF_BOT_BLOCKER=""
  if [[ -n "${CHANGELOG_PR_HEAD:-}" ]]; then
    tip="$CHANGELOG_PR_HEAD"
  elif git rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 && git merge-base --is-ancestor 'HEAD^1' "$base" 2>/dev/null; then
    tip='HEAD^2'
  fi
  from="$(git merge-base "$base" "$tip" 2>/dev/null)" || return 1
  commits="$(git log --format='%H%x09%an%x09%ae%x09%ce' "$from..$tip")" || return 1
  [[ -n "$commits" ]] || return 1
  # shellcheck source=/dev/null
  [[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
  while IFS=$'\t' read -r sha an ae ce; do
    CF_BOT_BLOCKER="commit ${sha:0:12} by $an <$ae>"
    [[ "$ce" == 'noreply@github.com' && "$an" == "$login" && "$ae" == "$email" ]] || return 1
    CF_BOT_BLOCKER=""
    verified="$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha" --jq '.commit.verification.verified' 2>/dev/null)" || return 1
    CF_BOT_BLOCKER="commit ${sha:0:12} carries $login's name but no signature GitHub verified"
    [[ "$verified" == true ]] || return 1
  done <<<"$commits"
  CF_BOT_BLOCKER=""
}

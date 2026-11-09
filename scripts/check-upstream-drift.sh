#!/usr/bin/env bash
# Check every docs/upstream page pinned to a git commit for upstream changes
# since that commit.
#
#   scripts/check-upstream-drift.sh [--page <file>]...            findings
#   scripts/check-upstream-drift.sh --report [--page <file>]...   list mode
#   scripts/check-upstream-drift.sh --links [--page <file>]...    link check
#   scripts/check-upstream-drift.sh --help
#
# The page forms (the git pin marker, row links, drift inputs, the `## Map`
# section and page status) are defined in docs/contracts/upstream-drift/
# README.md, "Pinned git upstreams". In short: a page whose marker line reads
# **Last audited upstream state:** `<owner>/<repo>@<40-hex sha>` [under `<scope>/`]
# is checked; links to that repository outside `## Map` are drift inputs for any
# change under them; a `## Map` link counts only when its unit is removed; a file
# added under the scope that no link covers is a new unit. A marker carrying a
# backticked `<owner>/<repo>@<hex>` that fails the form exits 2. Other markers
# (`main@<short sha>`, `changelog through`) are skipped.
#
# Trees are read with `gh api 'repos/<o>/<r>/git/trees/<sha>:<path>?recursive=1'`
# at the pin and at upstream HEAD. A truncated tree, a failed call, or a tree
# path holding a control character exits 2 and is never a clean report. When an
# owner's IP allow list refuses the token, that owner's calls retry anonymously
# with curl; a page with any read still refused is reported
# `status=unreachable`, named on stderr, and skipped; --report goes on and exits
# by drift alone, the other modes exit 2 after every page is read.
#
# Fixture seam, for tests: with UPSTREAM_DRIFT_FIXTURE_DIR set, gh is not used.
# <dir>/<owner>__<repo>/HEAD holds a SHA; <dir>/<owner>__<repo>/<sha>.tree
# holds `<blob sha> <repo-relative path>` lines for the whole tree; a line
# reading `truncated` marks a truncated read. A missing file exits 2.
#
# Output follows the check-script contract (scripts/README.md, "The check-script
# contract"): findings on stderr, the clean statement on stdout; --report prints
# its report on stdout for exit 0 and 1. Exit: 0 clean, 1 drift (or a bad link
# under --links), 2 environment or usage; on exit 2 nothing reaches stdout.
# Read-only: the script writes no file.
set -uo pipefail
# In a job, each gh call keeps its rate-limit reading for the job-end
# api-budget notice (.github/actions/log-api-budget).
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2
SELF="check-upstream-drift"

usage() {
  printf 'usage: %s [--report | --links] [--page <file>]... | --help\n' "${0##*/}"
}

bad_usage() {
  usage >&2
  exit 2
}

die() {
  printf '%s: %s\n' "$SELF" "$*" >&2
  exit 2
}

MODE=default
PAGES=()
while (($# > 0)); do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --report | --links)
    [[ "$MODE" == default ]] || bad_usage
    MODE="${1#--}"
    ;;
  --page)
    (($# >= 2)) || bad_usage
    PAGES+=("$2")
    shift
    ;;
  *) bad_usage ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required"
FIXTURE="${UPSTREAM_DRIFT_FIXTURE_DIR:-}"
if [[ -z "$FIXTURE" ]]; then
  # type -P: on a runner `gh` is also the api-budget wrapper function.
  type -P gh >/dev/null 2>&1 || die "gh is required (or set UPSTREAM_DRIFT_FIXTURE_DIR)"
fi

SHA_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'
MARKER_PREFIX='**Last audited upstream state:**'
# The backticks below are literal marker text, not command substitutions.
# shellcheck disable=SC2016
STRICT_RE='^\*\*Last audited upstream state:\*\* `([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)@([0-9a-f]{40})`(.*)$'
# shellcheck disable=SC2016
NEAR_RE='`[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9A-Fa-f]+`'
# shellcheck disable=SC2016
UNDER_RE='^ under `([^`]+)/`( .*)?$'
URL_RE="https://github\\.com/[^]()<>[:space:]\`\"'|[]+"

# --- page parsing ------------------------------------------------------------

# Set by parse_page: P_OWNER P_REPO P_PIN P_SCOPE, and per link L_LINE L_PATH
# L_REF L_MAP L_FORM (ok or bad-form), indexed together.
P_OWNER="" P_REPO="" P_PIN="" P_SCOPE=""
L_LINE=() L_PATH=() L_REF=() L_MAP=() L_FORM=() L_URL=()

lower() { printf '%s' "${1,,}"; }

url_decode() {
  local s="${1//+/ }"
  printf '%b' "${s//%/\\x}"
}

# parse_marker <page>: 0 git form (P_* set), 1 not the git form, 2 near-miss.
parse_marker() {
  local line rest
  line="$(grep -m1 -F -- "$MARKER_PREFIX" "$1")" || return 1
  if [[ "$line" != "$MARKER_PREFIX"* ]]; then
    # An indented or quoted marker that names a pin is a malformed record.
    [[ "$line" =~ $NEAR_RE ]] && return 2
    return 1
  fi
  if [[ "$line" =~ $STRICT_RE ]]; then
    P_OWNER="${BASH_REMATCH[1]}"
    P_REPO="${BASH_REMATCH[2]}"
    P_PIN="${BASH_REMATCH[3]}"
    rest="${BASH_REMATCH[4]}"
    P_SCOPE=""
    if [[ "$rest" =~ ^\ under([[:space:]\`]|$) ]]; then
      [[ "$rest" =~ $UNDER_RE ]] || return 2
      P_SCOPE="${BASH_REMATCH[1]}"
      [[ "$P_SCOPE" != /* && "$P_SCOPE" != *//* ]] || return 2
    fi
    return 0
  fi
  [[ "$line" =~ $NEAR_RE ]] && return 2
  return 1
}

# add_link <line> <map> <url>: records a link to the page's repository.
add_link() {
  local n="$1" map="$2" url="$3" rest owner repo kind ref path
  url="${url%%#*}"
  url="${url%%\?*}"
  while [[ "$url" == *[.,\;:] ]]; do url="${url%?}"; done
  rest="${url#https://github.com/}"
  owner="${rest%%/*}"
  rest="${rest#*/}"
  repo="${rest%%/*}"
  [[ "$(lower "$owner/$repo")" == "$(lower "$P_OWNER/$P_REPO")" ]] || return 0
  [[ "$rest" == */* ]] || return 0
  rest="${rest#*/}"
  kind="${rest%%/*}"
  [[ "$kind" == tree || "$kind" == blob ]] || return 0
  L_LINE+=("$n")
  L_MAP+=("$map")
  L_URL+=("$url")
  rest="${rest#"$kind"}"
  rest="${rest#/}"
  ref="${rest%%/*}"
  path="${rest#*/}"
  path="${path%/}"
  if [[ -z "$ref" || "$rest" != */* || -z "$path" ]]; then
    L_FORM+=(bad-form)
    L_REF+=("$ref")
    L_PATH+=("")
    return 0
  fi
  L_FORM+=(ok)
  L_REF+=("$ref")
  L_PATH+=("$(url_decode "$path")")
}

parse_links() { # <page>
  local n=0 in_map=0 line
  L_LINE=() L_PATH=() L_REF=() L_MAP=() L_FORM=() L_URL=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if [[ "$line" =~ ^##?[[:space:]] ]]; then
      if [[ "$line" =~ ^##[[:space:]]+Map[[:space:]]*$ ]]; then in_map=1; else in_map=0; fi
    fi
    while [[ "$line" =~ $URL_RE ]]; do
      add_link "$n" "$in_map" "${BASH_REMATCH[0]}"
      line="${line#*"${BASH_REMATCH[0]}"}"
    done
  done <"$1"
}

# --- reading upstream --------------------------------------------------------

declare -A HEADS=() TREES=() FIXTURE_FILES=() ANON=()
OUT_SHA=""
OUT_TREE=""
OUT_API=""
API_STATUS=""
PAGE_UNREACH="" # set when a read for the current page stays refused

# api <owner> <path>: GETs a REST path into OUT_API, the HTTP status of a
# failure in API_STATUS. Returns 1 on a failure, 5 when <owner>'s IP allow list
# refuses the token and the anonymous retry fails too.
api() {
  local o="$1" url="$2" resp
  API_STATUS=""
  if [[ -z "${ANON[$o]:-}" ]]; then
    OUT_API="$(gh api "$url" 2>/dev/null)" && return 0
    API_STATUS="$(jq -r '.status // empty' <<<"$OUT_API" 2>/dev/null)"
    jq -e '.message // "" | test("IP allow list")' <<<"$OUT_API" >/dev/null 2>&1 || return 1
    ANON[$o]=1
    printf '%s: %s: IP allow list refused the token; reading anonymously\n' "$SELF" "$o" >&2
  fi
  resp="$(curl -sS -H 'Accept: application/vnd.github+json' -w '\n%{http_code}' "https://api.github.com/$url" 2>/dev/null)" || {
    PAGE_UNREACH="curl failed"
    return 5
  }
  API_STATUS="${resp##*$'\n'}"
  OUT_API="${resp%$'\n'*}"
  [[ "$API_STATUS" == 2?? ]] && return 0
  [[ "$API_STATUS" == 404 || "$API_STATUS" == 422 ]] && return 1
  PAGE_UNREACH="HTTP ${API_STATUS:-none}"
  return 5
}

# check_tree_lines <text> <source>: dies on a truncated mark, a malformed line,
# or a path with a control character.
check_tree_lines() {
  local line path
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == truncated ]] && die "$2: tree read was truncated; no verdict"
    [[ "$line" =~ ^([0-9a-f]{40}|[0-9a-f]{64})\ (.+)$ ]] || die "$2: malformed tree line: $(printf '%q' "$line")"
    path="${BASH_REMATCH[2]}"
    [[ "$path" =~ [[:cntrl:]] ]] && die "$2: tree path holds a control character: $(printf '%q' "$path")"
  done <<<"$1"
}

head_sha() { # <owner> <repo>: sets OUT_SHA
  local key="$1/$2" sha
  if [[ -n "${HEADS[$key]:-}" ]]; then
    OUT_SHA="${HEADS[$key]}"
    return 0
  fi
  if [[ -n "$FIXTURE" ]]; then
    [[ -f "$FIXTURE/$1__$2/HEAD" ]] || die "fixture missing: $FIXTURE/$1__$2/HEAD"
    sha="$(tr -d '[:space:]' <"$FIXTURE/$1__$2/HEAD")"
  else
    api "$1" "repos/$1/$2/commits/HEAD"
    case $? in
    0) ;;
    5)
      OUT_SHA=""
      return 0
      ;;
    *) die "gh api repos/$1/$2/commits/HEAD failed${API_STATUS:+ (HTTP $API_STATUS)}" ;;
    esac
    sha="$(jq -r '.sha // empty' <<<"$OUT_API")"
  fi
  [[ "$sha" =~ $SHA_RE ]] || die "$key: HEAD is not a commit SHA: $(printf '%q' "$sha")"
  HEADS[$key]="$sha"
  OUT_SHA="$sha"
}

# filter_under <tree-text> <path>: lines whose path is <path> or under it.
filter_under() {
  local p="$2"
  [[ -z "$p" ]] && {
    printf '%s' "$1"
    return 0
  }
  awk -v p="$p" '{ q = substr($0, index($0, " ") + 1); if (q == p || index(q, p "/") == 1) print }' <<<"$1"
}

uri_path() { # percent-encodes every byte outside [A-Za-z0-9._~/-]
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
    [A-Za-z0-9._~/-]) out+="$c" ;;
    *) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

# gh_tree <o> <r> <sha> <path> [<recursive 1|0>]: sets OUT_TREE to
# `<blob> <path>` lines; returns 3 for 404 (absent), 4 for 422 (a blob).
gh_tree() {
  local o="$1" r="$2" sha="$3" p="$4" rec="${5:-1}" url status
  url="repos/$o/$r/git/trees/$sha"
  [[ -n "$p" ]] && url+=":$(uri_path "$p")"
  ((rec)) && url+="?recursive=1"
  if ! api "$o" "$url"; then
    status="$API_STATUS"
    [[ -n "$PAGE_UNREACH" ]] && return 5
    case "$status" in
    404) return 3 ;;
    422) return 4 ;;
    *) die "gh api $url failed${status:+ (HTTP $status)}" ;;
    esac
  fi
  OUT_TREE="$(jq -r --arg pre "${p:+$p/}" '
    if .truncated then "truncated"
    elif any(.tree[]; .path | explode | any(. < 32 or . == 127)) then "control"
    else .tree[] | select(.type == "blob") | "\(.sha) \($pre)\(.path)" end' <<<"$OUT_API")" ||
    die "gh api $url returned unreadable JSON"
  [[ "$OUT_TREE" == truncated ]] && die "$o/$r@${sha:0:12}:$p: tree read was truncated; no verdict"
  [[ "$OUT_TREE" == control ]] && die "$o/$r@${sha:0:12}:$p: a tree path holds a control character"
  return 0
}

# tree_list <o> <r> <sha> <path>: sets OUT_TREE to `<blob> <path>` lines for
# every file at or under <path> at <sha>; empty when the path is absent.
tree_list() {
  local o="$1" r="$2" sha="$3" p="$4" key="$1/$2@$3:$4" file rc dir
  if [[ -n "${TREES[$key]+set}" ]]; then
    OUT_TREE="${TREES[$key]}"
    return 0
  fi
  if [[ -n "$FIXTURE" ]]; then
    file="$FIXTURE/${o}__${r}/$sha.tree"
    if [[ -z "${FIXTURE_FILES[$file]+set}" ]]; then
      [[ -f "$file" ]] || die "fixture missing: $file"
      FIXTURE_FILES[$file]="$(cat "$file")"
      check_tree_lines "${FIXTURE_FILES[$file]}" "$o/$r@${sha:0:12}"
    fi
    OUT_TREE="$(filter_under "${FIXTURE_FILES[$file]}" "$p")"
  elif [[ -n "$P_SCOPE" && -n "$p" && "$p" != "$P_SCOPE" && "$p" == "$P_SCOPE"/* ]]; then
    tree_list "$o" "$r" "$sha" "$P_SCOPE"
    OUT_TREE="$(filter_under "$OUT_TREE" "$p")"
  else
    gh_tree "$o" "$r" "$sha" "$p"
    rc=$?
    if ((rc == 3 || rc == 5)); then
      OUT_TREE=""
    elif ((rc == 4)); then
      # A blob path: list its directory and keep the one entry.
      dir=""
      [[ "$p" == */* ]] && dir="${p%/*}"
      gh_tree "$o" "$r" "$sha" "$dir" 0
      rc=$?
      if ((rc == 0)); then
        # The listing is one level deep, so no entry sits under <path>.
        OUT_TREE="$(filter_under "$OUT_TREE" "$p")"
      else
        OUT_TREE=""
      fi
    fi
  fi
  [[ -n "$PAGE_UNREACH" ]] || TREES[$key]="$OUT_TREE"
}

# diff_trees <pin-text> <head-text>: prints `<A|M|D> <path>` sorted by path.
diff_trees() {
  awk '
    FNR == 1 { fileno++ }
    $0 == "" { next }
    {
      i = index($0, " "); s = substr($0, 1, i - 1); q = substr($0, i + 1)
      if (fileno == 1) pin[q] = s; else head[q] = s
    }
    END {
      for (q in head) {
        if (!(q in pin)) print q "\tA"
        else if (pin[q] != head[q]) print q "\tM"
      }
      for (q in pin) if (!(q in head)) print q "\tD"
    }' <(printf '%s\n' "$1") <(printf '%s\n' "$2") |
    sort | awk -F '\t' '{ print $2 " " $1 }'
}

# --- pages -------------------------------------------------------------------

EXPLICIT=$((${#PAGES[@]} > 0))
if ((!EXPLICIT)) && [[ -d "$ROOT/docs/upstream" ]]; then
  while IFS= read -r path; do
    PAGES+=("${path#"$ROOT"/}")
  done < <(find "$ROOT/docs/upstream" -type f -name '*.md' | sort)
fi

page_file() { # <page>: resolves a page argument to a readable file
  if [[ "$1" == /* || -f "$1" ]]; then printf '%s' "$1"; else printf '%s' "$ROOT/$1"; fi
}

GIT_PAGES=()
for page in ${PAGES[@]+"${PAGES[@]}"}; do
  file="$(page_file "$page")"
  [[ -f "$file" ]] || die "$page: no such file"
  parse_marker "$file"
  case $? in
  0) GIT_PAGES+=("$page") ;;
  2) die "$page: marker line names a pin but does not match the git form (see docs/contracts/upstream-drift/README.md, \"Pinned git upstreams\")" ;;
  *) ((EXPLICIT)) && die "$page: no git pin marker" ;;
  esac
done

FINDINGS=()
REPORT=()
UNREACHABLE=()

# unreachable_page: records the current page as unreachable; its other results
# are dropped.
unreachable_page() {
  UNREACHABLE+=("$page: $o/$r refused the token (IP allow list) and an anonymous read ($PAGE_UNREACH); not checked")
  REPORT+=("page repo=$o/$r pin=${pin:0:12} head=unknown status=unreachable path=$page")
}
drifted=0
links_checked=0

for page in ${GIT_PAGES[@]+"${GIT_PAGES[@]}"}; do
  file="$(page_file "$page")"
  parse_marker "$file"
  parse_links "$file"
  o="$P_OWNER" r="$P_REPO" pin="$P_PIN" scope="$P_SCOPE"
  PAGE_UNREACH=""
  # Without this, an unknown pin reads as every path absent. The fixture seam
  # already exits 2 on a missing <pin>.tree file.
  if [[ -z "$FIXTURE" ]]; then
    api "$o" "repos/$o/$r/git/commits/$pin"
    case $? in
    0) ;;
    5)
      unreachable_page
      continue
      ;;
    *) die "$page: pin $o/$r@$pin is not a commit upstream (or gh api failed): $(jq -r '.message // empty' <<<"$OUT_API" 2>/dev/null)${API_STATUS:+ (HTTP $API_STATUS)}" ;;
    esac
  fi

  # A scope absent at the pin is a malformed record, not drift: both trees
  # would read empty and new-unit detection would be silently off.
  if [[ -n "$scope" ]]; then
    tree_list "$o" "$r" "$pin" "$scope"
    if [[ -n "$PAGE_UNREACH" ]]; then
      unreachable_page
      continue
    fi
    [[ -n "$OUT_TREE" ]] || die "$page: scope $scope/ does not exist in $o/$r@$pin"
  fi

  if [[ "$MODE" == links ]]; then
    found=${#FINDINGS[@]}
    for i in "${!L_LINE[@]}"; do
      links_checked=$((links_checked + 1))
      status="${L_FORM[i]}"
      if [[ "$status" == ok && "${L_REF[i]}" != "$pin" ]]; then
        status=wrong-sha
      elif [[ "$status" == ok ]]; then
        tree_list "$o" "$r" "$pin" "${L_PATH[i]}"
        [[ -n "$OUT_TREE" ]] || status=missing-at-pin
      fi
      [[ "$status" == ok ]] || FINDINGS+=("$page:${L_LINE[i]}: $status ${L_URL[i]}")
    done
    if [[ -n "$PAGE_UNREACH" ]]; then
      FINDINGS=("${FINDINGS[@]:0:found}")
      unreachable_page
    fi
    continue
  fi

  head_sha "$o" "$r"
  head="$OUT_SHA"
  if [[ -n "$PAGE_UNREACH" ]]; then
    unreachable_page
    continue
  fi
  page_events=()
  page_report=()
  covered=()

  for i in "${!L_LINE[@]}"; do
    [[ "${L_FORM[i]}" == ok ]] || continue
    covered+=("${L_PATH[i]}")
  done

  if [[ -z "$scope" ]] && ((${#covered[@]} == 0)); then
    REPORT+=("page repo=$o/$r pin=${pin:0:12} head=${head:0:12} status=untracked path=$page")
    continue
  fi

  for i in "${!L_LINE[@]}"; do
    [[ "${L_FORM[i]}" == ok ]] || continue
    p="${L_PATH[i]}" n="${L_LINE[i]}"
    tree_list "$o" "$r" "$pin" "$p"
    at_pin="$OUT_TREE"
    tree_list "$o" "$r" "$head" "$p"
    at_head="$OUT_TREE"
    if ((L_MAP[i])); then
      if [[ -n "$at_pin" && -z "$at_head" ]]; then
        page_events+=("$page:$n: $o/$r removed unit $p")
        page_report+=("removed-unit path=$p")
      fi
      continue
    fi
    changes="$(diff_trees "$at_pin" "$at_head")"
    if [[ -z "$changes" ]]; then
      page_report+=("row line=$n status=unchanged path=$p")
      continue
    fi
    while IFS= read -r change; do
      page_events+=("$page:$n: $o/$r ${change%% *} ${change#* }")
      page_report+=("row line=$n status=${change%% *} path=${change#* }")
    done <<<"$changes"
  done

  if [[ -n "$scope" ]]; then
    tree_list "$o" "$r" "$pin" "$scope"
    at_pin="$OUT_TREE"
    tree_list "$o" "$r" "$head" "$scope"
    at_head="$OUT_TREE"
    while IFS= read -r change; do
      [[ "$change" == "A "* ]] || continue
      added="${change#A }"
      hit=0
      for c in ${covered[@]+"${covered[@]}"}; do
        if [[ "$added" == "$c" || "$added" == "$c"/* ]]; then
          hit=1
          break
        fi
      done
      ((hit)) && continue
      page_events+=("$page: $o/$r new unit $added")
      page_report+=("new-unit path=$added")
    done < <(diff_trees "$at_pin" "$at_head")
  fi

  if [[ -n "$PAGE_UNREACH" ]]; then
    unreachable_page
    continue
  fi
  status=clean
  if ((${#page_events[@]} > 0)); then
    status=drift
    drifted=$((drifted + 1))
    FINDINGS+=("${page_events[@]}")
  fi
  REPORT+=("page repo=$o/$r pin=${pin:0:12} head=${head:0:12} status=$status path=$page")
  # Row lines first in page order, then units, as the report contract lists.
  for kind in row new-unit removed-unit; do
    for line in ${page_report[@]+"${page_report[@]}"}; do
      [[ "$line" == "$kind "* ]] && REPORT+=("$line")
    done
  done
done

# --- output ------------------------------------------------------------------

if ((${#UNREACHABLE[@]} > 0)); then
  printf '%s: %s\n' "$SELF" "${UNREACHABLE[@]}" >&2
  [[ "$MODE" == report ]] || exit 2
fi

if [[ "$MODE" == links ]]; then
  if ((${#FINDINGS[@]} > 0)); then
    printf '%s\n' "${FINDINGS[@]}" >&2
    printf '%s: %d of %d link(s) are not ok at the page pin.\n' "$SELF" "${#FINDINGS[@]}" "$links_checked" >&2
    exit 1
  fi
  printf 'upstream records: %d links ok across %d pages\n' "$links_checked" "${#GIT_PAGES[@]}"
  exit 0
fi

if [[ "$MODE" == report ]]; then
  ((${#REPORT[@]} > 0)) && printf '%s\n' "${REPORT[@]}"
fi

if ((drifted > 0)); then
  printf '%s\n' "${FINDINGS[@]}" >&2
  printf '%s: %d of %d page(s) show upstream drift; re-audit the rows named above (docs/contracts/upstream-drift/README.md, "Pinned git upstreams").\n' \
    "$SELF" "$drifted" "${#GIT_PAGES[@]}" >&2
  exit 1
fi

[[ "$MODE" == report ]] || printf 'upstream records: %d pages, no drift\n' "${#GIT_PAGES[@]}"
exit 0

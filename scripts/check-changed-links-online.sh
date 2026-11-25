#!/usr/bin/env bash
# Check, online, the external links a pull request adds or changes in markdown.
#
#   check-changed-links-online.sh [--list] <base-ref>
#
# lychee extracts the links of each markdown file the diff `<base-ref>...HEAD`
# adds or modifies, with the same parser and lychee.toml the offline lane and the
# weekly online run use, so code spans, fenced blocks and excluded URLs are left
# out as they are there. A link is kept when it appears on an added line. lychee
# then checks just those with the network on; lychee.toml's accept list keeps a
# 429, a 5xx or a timeout from failing. --list prints the kept links and checks
# nothing. LYCHEE names the binary (default lychee), LYCHEE_CONFIG the ruleset
# (default: https://github.com/melodic-software/standards/blob/main/components/lychee/README.md#defaults-extensions-and-overrides). Exit status follows scripts/README.md, "The
# check-script contract".
set -euo pipefail
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
me=check-changed-links-online
parser=${BASH_SOURCE[0]%/*}/../lib/parse-concern-value.sh

list=0
if [[ ${1:-} == --list ]]; then
  list=1
  shift
fi
if [[ $# -ne 1 || -z $1 ]]; then
  echo "usage: $0 [--list] <base-ref>" >&2
  exit 2
fi
base=$1
lychee=${LYCHEE:-lychee}
if ! command -v "$lychee" >/dev/null 2>&1; then
  echo "$me: lychee not found ($lychee)" >&2
  exit 2
fi
temporary=()
trap 'rm -f "${temporary[@]}"' EXIT

configs=()
resolve_configs() {
  if [[ -n ${LYCHEE_CONFIG:-} ]]; then
    configs=(--config "$LYCHEE_CONFIG")
    return
  fi
  local standards repository
  if [[ -n ${STANDARDS_DIR:-} ]]; then
    standards=$STANDARDS_DIR/lychee.toml
    [[ -f $standards ]] || { echo "$me: the standards checkout $STANDARDS_DIR has no lychee.toml" >&2; exit 2; }
  else
    repository=$(bash "$parser" docs/conventions/source-control.yaml standards_repository)
    [[ $repository =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
      { echo "$me: no standards checkout (STANDARDS_DIR) and no standards_repository in docs/conventions/source-control.yaml" >&2; exit 2; }
    standards=$(mktemp --suffix=.toml)
    temporary+=("$standards")
    gh api -H 'Accept: application/vnd.github.raw' "repos/$repository/contents/lychee.toml" >"$standards" ||
      { echo "$me: $repository lychee.toml could not be read" >&2; exit 2; }
  fi
  configs=(--config "$standards")
  if [[ -f lychee.toml ]]; then configs+=(--config lychee.toml); fi
}

paths=(-- '*.md'
  ':(exclude)plugins/attribution/skills/audit/evals/fixtures/golden/**'
  ':(exclude)scripts/fixtures/hooks-lifecycle-table.md')
if ! files_out=$(git diff --name-only --diff-filter=AMRC "$base...HEAD" "${paths[@]}") ||
  ! added=$(git diff -U0 --no-color --no-ext-diff --dst-prefix=b/ "$base...HEAD" "${paths[@]}"); then
  echo "$me: could not read the diff against $base" >&2
  exit 2
fi
added=$(grep -vE '^\+\+\+ (b/|/dev/null)' <<<"$added" | sed -n 's/^+//p' || true)
mapfile -t files < <(printf '%s' "$files_out")

urls=()
if ((${#files[@]})); then
  resolve_configs
  if ! dump=$("$lychee" --dump --no-progress "${configs[@]}" "${files[@]}" 2>/dev/null); then
    echo "$me: lychee could not extract the links of the changed files" >&2
    exit 2
  fi
  # lychee may add a trailing slash to a bare host; match without it.
  while IFS= read -r url; do
    if [[ $url =~ ^https?:// && $added == *"${url%/}"* ]]; then urls+=("$url"); fi
  done < <(LC_ALL=C sort -u <<<"$dump")
fi

self=${SELF_REPO:-${GITHUB_REPOSITORY:-}}
if [[ -n $self ]] && ((${#urls[@]})); then
  kept=()
  for url in "${urls[@]}"; do
    path=
    for kind in blob tree; do
      prefix="https://github.com/$self/$kind/${base#origin/}/"
      [[ $url == "$prefix"* ]] && path=${url#"$prefix"} && path=${path%%[#?]*}
    done
    if [[ -n $path ]] && git cat-file -e "HEAD:${path%/}" 2>/dev/null; then continue; fi
    kept+=("$url")
  done
  urls=("${kept[@]}")
fi

if ((list)); then
  ((${#urls[@]} == 0)) || printf '%s\n' "${urls[@]}"
  exit 0
fi
if ((${#urls[@]} == 0)); then
  echo "$me: no external links added or changed in markdown"
  exit 0
fi

input=$(mktemp --suffix=.md)
temporary+=("$input")
printf '<%s>\n' "${urls[@]}" >"$input"
rc=0
report=$("$lychee" --no-progress "${configs[@]}" "$input" 2>&1) || rc=$?
case $rc in
  0) echo "$me: ${#urls[@]} added or changed external link(s) resolve" ;;
  2)
    printf '%s\n' "$report" >&2
    broken=0
    declare -A seen=()
    while IFS='|' read -r head reason; do
      url=${head#*\] }
      url=${url%%' (at '*}
      url=${url%"${url##*[![:space:]]}"}
      [[ -n ${seen[$url]:-} ]] && continue
      seen[$url]=1
      at=$(grep -HnF -- "$url" "${files[@]}" 2>/dev/null | head -n 1) || true
      file=${at%%:*} line=${at#*:} line=${line%%:*}
      reason=${reason#"${reason%%[![:space:]]*}"}
      if [[ -n $at ]]; then
        echo "::error file=$file,line=$line::broken link $url: $reason" >&2
      else
        echo "::error::broken link $url: $reason" >&2
      fi
      broken=$((broken + 1))
    done < <(grep -E '^\[([0-9]{3}|ERROR|TIMEOUT)\] ' <<<"$report")
    if ((broken == 0)); then
      echo "$me: lychee reported broken links in a form this script does not parse; see its report above" >&2
    else
      echo "$me: $broken of ${#urls[@]} added or changed external link(s) broken" >&2
    fi
    exit 1
    ;;
  *) printf '%s\n' "$report" >&2; echo "$me: lychee failed (exit $rc)" >&2; exit 2 ;;
esac

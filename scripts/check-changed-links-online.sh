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
# (default lychee.toml). Exit status follows scripts/README.md, "The
# check-script contract".
set -euo pipefail
me=check-changed-links-online

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
config=${LYCHEE_CONFIG:-lychee.toml}
if ! command -v "$lychee" >/dev/null 2>&1; then
  echo "$me: lychee not found ($lychee)" >&2
  exit 2
fi

# The excludes are test data whose links are meant not to resolve, as the
# offline lane excludes them. A diff git cannot read is exit 2, never "no links".
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
  if ! dump=$("$lychee" --dump --no-progress --config "$config" "${files[@]}" 2>/dev/null); then
    echo "$me: lychee could not extract the links of the changed files" >&2
    exit 2
  fi
  # lychee may add a trailing slash to a bare host; match without it.
  while IFS= read -r url; do
    if [[ $url =~ ^https?:// && $added == *"${url%/}"* ]]; then urls+=("$url"); fi
  done < <(LC_ALL=C sort -u <<<"$dump")
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
trap 'rm -f "$input"' EXIT
printf '<%s>\n' "${urls[@]}" >"$input"
rc=0
report=$("$lychee" --no-progress --config "$config" "$input" 2>&1) || rc=$?
case $rc in
  0) echo "$me: ${#urls[@]} added or changed external link(s) resolve" ;;
  2) printf '%s\n' "$report" >&2; exit 1 ;;
  *) printf '%s\n' "$report" >&2; echo "$me: lychee failed (exit $rc)" >&2; exit 2 ;;
esac

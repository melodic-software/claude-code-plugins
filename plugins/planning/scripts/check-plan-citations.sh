#!/usr/bin/env bash
# Citation gate for a drafted PLAN.md (/planning:plan Step 4.7).
#
# A plan that cites `path:line` for a claim is only as good as the citation: a
# path that was renamed, or a line number past the end of the file, sends the
# implementing session to code that is not there. This gate resolves every
# citation against one named commit, with no model involvement, and fails on any
# that does not exist there.
#
#   citation        a path from the repository root, then `:` and one or more
#                   comma-separated `<line>` or `<start>-<end>` items, as in
#                   scripts/build.sh:12, src/app.ts:40-58 or src/app.ts:3,9-11;
#                   each item is checked on its own. The path holds letters,
#                   digits and any of `_ . / + -`, carries at least one letter,
#                   and holds a `/` or a `.`, so a time (10:30) or a bare word
#                   (Q1:2) is not one. A leading `./` is dropped. A match is not
#                   a citation when it continues something larger: right after a
#                   path character or one of `: ~ @ $ ] ) }` (a URL, a home path,
#                   a package pin, a variable), or followed by more word text
#                   (`:12:3`, `:1.2.3`, `:20-alpine`, `:12abc`). A dotted host
#                   and port (db.internal:5432) still reads as a citation
#   missing-path    the path is not in the commit's tree
#   not-a-file      the path names a directory (or a submodule), not a file
#   line-zero       a line number is 0
#   past-end        a line number is past the file's last line at the commit
#   reversed        a range's end line is before its start line
#
# Lines inside fenced code blocks are ignored: a fence holds tool output or an
# example, whose `file:line` text is not the plan's own claim. A fence may open
# inside a block quote or a list item, and closes only on the same character
# with at least the opening length and no info string; a fence left open exits
# 2, since it would hide every citation after it. A line carrying
# <!-- citation-example --> is ignored too.
#
# A fence whose info string starts with `shape` anchors a code shape:
# `shape <path>[#<symbol>][ L<n>]`. Only an outermost fence counts, so a shape
# fence quoted inside a longer fence is not checked. The path is read like a
# citation path; a file path needs `#<symbol>`, a token with no spaces that
# `git grep -w -F -e <symbol>` finds in it at the commit, and a directory path
# needs none (a symbol it carries is searched for in that directory).
#   shape-missing-path    the path is not in the commit's tree
#   shape-missing-symbol  a file path has no symbol, or the symbol is not found
#   shape-past-end        L<n> is past the file's last line
#   shape-not-a-file      L<n> on a directory, or the path names a submodule
#   shape-malformed       no path, an empty `#`, or a second word that is not L<n>
#   shape-line            a warning, not a failure: line <n> lacks the symbol
#
# The commit the check ran at is printed as `commit=<full sha>`; the plan records
# it on its `Citations checked at:` line, so a later reader knows which tree the
# line numbers describe.
#
# Exit 0 = every citation and shape anchor resolves (a plan with neither passes)
# Exit 1 = at least one citation or shape anchor does not resolve
# Exit 2 = usage or environment error (missing file, not a git repository,
#          a commit that does not resolve, an unterminated fence, ...)
#
# Usage:
#   bash check-plan-citations.sh [--commit <rev>] [--repo <dir>] <PLAN.md>
#   bash check-plan-citations.sh --help
#
#   --commit  the commit the citations are checked at (default HEAD)
#   --repo    the repository the paths are relative to (default the current
#             directory's repository)
#
# Output (stdout, greppable): one
# `citation=<plan line>:<path>:<lines> status=fail reason=<reason>` line per
# failing citation (a past-end reason adds ` last-line=<n>`), one
# `shape=<plan line>:<info after shape> status=<fail|warn> reason=<reason>` line
# per failing or warned shape anchor, a `shapes=<n> failed=<n> warned=<n>` line,
# then a closing `citations=<n> failed=<n> commit=<sha> status=<ok|fail>` line,
# whose status is fail when a citation or a shape anchor failed.

set -uo pipefail

usage() {
  sed -n '/^# Citation gate/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  echo "error: $1" >&2
  exit 2
}

plan=""
rev="HEAD"
repo="."
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --commit)
    [[ $# -ge 2 && -n "$2" ]] || die "--commit needs a value"
    rev="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 && -n "$2" ]] || die "--repo needs a value"
    repo="$2"
    shift 2
    ;;
  -*)
    die "unknown option: $1"
    ;;
  *)
    [[ -z "$plan" ]] || die "exactly one PLAN.md path is expected"
    plan="$1"
    shift
    ;;
  esac
done

[[ -n "$plan" ]] || die "a PLAN.md path is required (see --help)"
[[ -f "$plan" ]] || die "not a file: $plan"
[[ -r "$plan" ]] || die "not readable: $plan"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $repo"
commit="$(git -C "$repo" rev-parse --verify --quiet "$rev^{commit}")" || die "not a commit: $rev"

# One citation per line: C TAB <plan line> TAB <path> TAB <start> TAB <end>.
# One shape anchor per line, fields split by US (\037) so an empty one stays:
# S US <plan line> US <ok|malformed> US <path> US <symbol> US <n> US <label>.
# Exit 4 = a fence was still open at end of file.
citations="$(
  LC_ALL=C awk '
    function shape_row(info,   words, n, hash, path, symbol, line, form) {
      sub(/^[ \t]*shape/, "", info)
      sub(/^[ \t]+/, "", info)
      sub(/[ \t]+$/, "", info)
      gsub(/[ \t]+/, " ", info)
      n = split(info, words, / /)
      form = "ok"
      path = symbol = line = ""
      if (n < 1 || n > 2) form = "malformed"
      else {
        hash = index(words[1], "#")
        path = hash ? substr(words[1], 1, hash - 1) : words[1]
        symbol = hash ? substr(words[1], hash + 1) : ""
        sub(/^(\.\/)+/, "", path)
        sub(/\/+$/, "", path)
        if (path == "" || (hash && symbol == "")) form = "malformed"
        if (n == 2) {
          if (words[2] ~ /^L[1-9][0-9]*$/) line = substr(words[2], 2)
          else form = "malformed"
        }
      }
      printf "S\037%d\037%s\037%s\037%s\037%s\037%s\n", NR, form, path, symbol, line, info
    }
    { sub(/\r$/, "") }
    match($0, /^([ \t]*>)*[ \t]*(([-*+]|[0-9]+[.)])[ \t]+)?(```+|~~~+)/) {
      fence = substr($0, RSTART, RLENGTH)
      info = substr($0, RSTART + RLENGTH)
      sub(/^[^`~]*/, "", fence)
      bare = (info ~ /^[ \t]*$/)
      if (!in_fence) {
        in_fence = 1
        fence_ch = substr(fence, 1, 1)
        fence_len = length(fence)
        if (info ~ /^[ \t]*shape([ \t]|$)/) shape_row(info)
        next
      }
      if (substr(fence, 1, 1) == fence_ch && length(fence) >= fence_len && bare) in_fence = 0
      next
    }
    in_fence { next }
    /<!-- citation-example -->/ { next }
    {
      line = $0
      offset = 0
      while (match(line, /[A-Za-z0-9_.\/+-]+:[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*/)) {
        start = RSTART
        len = RLENGTH
        token = substr(line, start, len)
        before = (offset + start > 1) ? substr($0, offset + start - 1, 1) : ""
        rest = substr(line, start + len)
        line = rest
        offset += start + len - 1
        if (before ~ /[]A-Za-z0-9_.\/+:~@$)}-]/) continue
        if (rest ~ /^[A-Za-z0-9_.:\/-]*[A-Za-z0-9_]/) continue
        path = token
        sub(/:[0-9,-]+$/, "", path)
        spec = substr(token, length(path) + 2)
        sub(/^(\.\/)+/, "", path)
        if (path !~ /[A-Za-z]/ || path !~ /[\/.]/) continue
        n = split(spec, items, ",")
        for (i = 1; i <= n; i++) {
          first = items[i]
          last = items[i]
          if (index(first, "-")) { sub(/-.*/, "", first); sub(/^[0-9]+-/, "", last) }
          printf "C\t%d\t%s\t%s\t%s\n", NR, path, first, last
        }
      }
    }
    END { if (in_fence) exit 4 }
  ' "$plan"
)"
case $? in
0) ;;
4) die "unterminated fenced block in: $plan (every citation after it is hidden; close the fence)" ;;
*) die "could not parse: $plan" ;;
esac

# One row per distinct path: P TAB <path> TAB <blob|missing|other> TAB <line count>.
paths=""
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  kind="$(git -C "$repo" cat-file -t "$commit:$path" 2>/dev/null)" || kind="missing"
  count=0
  if [[ "$kind" == blob ]]; then
    count="$(git -C "$repo" cat-file blob "$commit:$path" | LC_ALL=C awk 'END { print NR }')" ||
      die "could not read $path at $commit"
  elif [[ "$kind" != missing ]]; then
    kind="other"
  fi
  paths+="P"$'\t'"$path"$'\t'"$kind"$'\t'"$count"$'\n'
done < <(printf '%s\n' "$citations" | cut -s -f3 | LC_ALL=C sort -u)

# The path rows come first in one stream, so every citation row finds its path.
report="$(
  printf '%s%s\n' "$paths" "$citations" | LC_ALL=C awk -F'\t' '
    $1 == "P" { kind[$2] = $3; count[$2] = $4; next }
    $1 != "C" { next }
    {
      total++
      reason = ""
      if (!($3 in kind)) reason = "unresolved"
      else if (kind[$3] == "missing") reason = "missing-path"
      else if (kind[$3] == "other") reason = "not-a-file"
      else if ($4 == 0 || $5 == 0) reason = "line-zero"
      else if ($5 < $4) reason = "reversed"
      else if ($5 > count[$3]) reason = "past-end last-line=" count[$3]
      if (reason == "") next
      failed++
      cited = ($4 == $5) ? $4 : $4 "-" $5
      printf "citation=%s:%s:%s status=fail reason=%s\n", $2, $3, cited, reason
    }
    END { printf "citations=%d failed=%d\n", total, failed }
  '
)" || die "could not grade: $plan"

shape_report=""
shapes=0
shape_failed=0
shape_warned=0
while IFS=$'\037' read -r tag at form path symbol line label; do
  [[ "$tag" == S ]] || continue
  shapes=$((shapes + 1))
  status="fail"
  reason=""
  if [[ "$form" != ok ]]; then
    reason="shape-malformed"
  elif ! kind="$(git -C "$repo" cat-file -t "$commit:$path" 2>/dev/null)"; then
    reason="shape-missing-path"
  elif [[ "$kind" != blob && "$kind" != tree ]] || [[ "$kind" == tree && -n "$line" ]]; then
    reason="shape-not-a-file"
  elif [[ "$kind" == blob && -z "$symbol" ]]; then
    reason="shape-missing-symbol"
  elif [[ -n "$symbol" ]]; then
    git -C "$repo" grep -q -w -F -e "$symbol" "$commit" -- ":(top,literal)$path" >/dev/null 2>&1
    case $? in
    0) ;;
    1) reason="shape-missing-symbol" ;;
    *) die "could not search $path at $commit" ;;
    esac
  fi
  if [[ -z "$reason" && -n "$line" ]]; then
    read_out="$(git -C "$repo" cat-file blob "$commit:$path" |
      LC_ALL=C awk -v n="$line" 'NR == n { text = $0 } END { print NR " " text }')" ||
      die "could not read $path at $commit"
    count="${read_out%% *}"
    text="${read_out#* }"
    if [[ "$line" -gt "$count" ]]; then
      reason="shape-past-end last-line=$count"
    elif ! grep -q -w -F -e "$symbol" <<<"$text"; then
      status="warn"
      reason="shape-line"
    fi
  fi
  [[ -n "$reason" ]] || continue
  if [[ "$status" == fail ]]; then
    shape_failed=$((shape_failed + 1))
  else
    shape_warned=$((shape_warned + 1))
  fi
  shape_report+="shape=$at:$label status=$status reason=$reason"$'\n'
done < <(printf '%s\n' "$citations")

summary="${report##*$'\n'}"
failed="${summary##*failed=}"
[[ "$summary" == citations=*" failed="* && "$failed" =~ ^[0-9]+$ ]] || die "could not grade: $plan"
[[ "$report" != *$'\n'* ]] || printf '%s\n' "${report%$'\n'*}"
printf '%s' "$shape_report"
printf 'shapes=%d failed=%d warned=%d\n' "$shapes" "$shape_failed" "$shape_warned"
if [[ "$failed" -eq 0 && "$shape_failed" -eq 0 ]]; then
  printf '%s commit=%s status=ok\n' "$summary" "$commit"
  exit 0
fi
printf '%s commit=%s status=fail\n' "$summary" "$commit"
exit 1

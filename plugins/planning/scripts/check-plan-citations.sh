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
# The commit the check ran at is printed as `commit=<full sha>`; the plan records
# it on its `Citations checked at:` line, so a later reader knows which tree the
# line numbers describe.
#
# Exit 0 = every citation resolves (a plan with no citation passes)
# Exit 1 = at least one citation does not resolve
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
# failing citation (a past-end reason adds ` last-line=<n>`), then a closing
# `citations=<n> failed=<n> commit=<sha> status=<ok|fail>` line.

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
# Exit 4 = a fence was still open at end of file.
citations="$(
  LC_ALL=C awk '
    { sub(/\r$/, "") }
    match($0, /^([ \t]*>)*[ \t]*(([-*+]|[0-9]+[.)])[ \t]+)?(```+|~~~+)/) {
      fence = substr($0, RSTART, RLENGTH)
      sub(/^[^`~]*/, "", fence)
      bare = (substr($0, RSTART + RLENGTH) ~ /^[ \t]*$/)
      if (!in_fence) { in_fence = 1; fence_ch = substr(fence, 1, 1); fence_len = length(fence); next }
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
done < <(printf '%s\n' "$citations" | cut -f3 | LC_ALL=C sort -u)

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

summary="${report##*$'\n'}"
failed="${summary##*failed=}"
[[ "$summary" == citations=*" failed="* && "$failed" =~ ^[0-9]+$ ]] || die "could not grade: $plan"
[[ "$report" != *$'\n'* ]] || printf '%s\n' "${report%$'\n'*}"
if [[ "$failed" -eq 0 ]]; then
  printf '%s commit=%s status=ok\n' "$summary" "$commit"
  exit 0
fi
printf '%s commit=%s status=fail\n' "$summary" "$commit"
exit 1

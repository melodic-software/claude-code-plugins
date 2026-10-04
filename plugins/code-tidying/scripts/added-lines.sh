#!/usr/bin/env bash
# added-lines.sh: list the line ranges a branch adds, for the `--added-since <base>`
# scope of audit-comment-residue and dissolve-comments. Read-only.
#
# Usage: added-lines.sh <base>
#
# Compares the working tree against the merge base of <base> and HEAD, so lines the
# base side added after the branch point never count as this branch's. Tracked files
# only; a deleted file adds nothing; a rename reports only its edited lines.
#
# Output: one row per added hunk, `<start><TAB><count><TAB><path>`, path last and
# repository-relative. Paths come from `git diff -z`, so a space survives whole.
# Exit: 0 on success (no rows when nothing was added); 2 on a missing or unknown base,
# outside a repository, when any changed path holds a control character, which
# would make a row ambiguous, or when a hunk header's start or count is not digits
# (rows printed before that point are not to be trusted). Every diff passes
# --no-ext-diff and --no-textconv, so a configured external diff or textconv driver
# never shapes the output this script parses.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" || "$1" == -* ]]; then
  echo "usage: added-lines.sh <base>" >&2
  exit 2
fi
base="$1"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "added-lines.sh: not inside a git work tree" >&2
  exit 2
}
cd "$(git rev-parse --show-toplevel)"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || {
  echo "added-lines.sh: unknown base" >&2
  exit 2
}
mb="$(git merge-base "$base" HEAD)" || {
  echo "added-lines.sh: no merge base with HEAD" >&2
  exit 2
}

# Records: status, then one path (two for a rename or copy), NUL-terminated.
records=()
while IFS= read -r -d '' field; do
  records+=("$field")
done < <(git diff --no-ext-diff --no-textconv -z -M --name-status "$mb")

for field in ${records[@]+"${records[@]}"}; do
  if [[ "$field" =~ [[:cntrl:]] ]]; then
    echo "added-lines.sh: a changed path holds a control character; no rows printed" >&2
    exit 2
  fi
done

# Print the added hunks of one diff, labelled with the path given.
hunks() {
  local path="$1" line spec start count
  shift
  while IFS= read -r line; do
    [[ "$line" == '@@ '* ]] || continue
    spec="${line#@@ -* +}"
    spec="${spec%% @@*}"
    start="${spec%%,*}"
    if [[ "$spec" == *,* ]]; then count="${spec#*,}"; else count=1; fi
    # Never let a header field reach arithmetic unchecked: bash evaluates an array subscript
    # inside (( )), so a crafted field would run a command.
    if [[ ! "$start" =~ ^[0-9]+$ || ! "$count" =~ ^[0-9]+$ ]]; then
      echo "added-lines.sh: a hunk header is not git's @@ form; no rows trusted" >&2
      return 2
    fi
    if ((count > 0)); then printf '%s\t%s\t%s\n' "$start" "$count" "$path"; fi
  done < <(git --literal-pathspecs diff --no-ext-diff --no-textconv -U0 -M --no-color "$mb" -- "$@")
}

i=0
while ((i < ${#records[@]})); do
  status="${records[i]}"
  case "$status" in
  R* | C*)
    hunks "${records[i + 2]}" "${records[i + 1]}" "${records[i + 2]}"
    i=$((i + 3))
    ;;
  D*) i=$((i + 2)) ;;
  *)
    hunks "${records[i + 1]}" "${records[i + 1]}"
    i=$((i + 2))
    ;;
  esac
done
exit 0

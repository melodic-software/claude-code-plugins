#!/usr/bin/env bash
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

records=()
while IFS= read -r -d '' field; do
  records+=("$field")
done < <(git diff --no-ext-diff --no-textconv -z -M --name-status "$mb")
wait "$!" || {
  echo "added-lines.sh: git diff --name-status failed; no rows printed" >&2
  exit 2
}

if [[ "${records[*]-}" =~ [[:cntrl:]] ]]; then
  echo "added-lines.sh: a changed path holds a control character; no rows printed" >&2
  exit 2
fi

hunks() {
  local path="$1" line spec start count diff
  shift
  diff="$(git --literal-pathspecs diff --no-ext-diff --no-textconv -U0 -M --no-color "$mb" -- "$@")" || {
    echo "added-lines.sh: git diff failed for a changed path; no rows trusted" >&2
    return 2
  }
  while IFS= read -r line; do
    [[ "$line" == '@@ '* ]] || continue
    spec="${line#@@ -* +}"
    spec="${spec%% @@*}"
    start="${spec%%,*}"
    if [[ "$spec" == *,* ]]; then count="${spec#*,}"; else count=1; fi
    if [[ ! "$start" =~ ^[0-9]+$ || ! "$count" =~ ^[0-9]+$ ]]; then
      echo "added-lines.sh: a hunk header is not git's @@ form; no rows trusted" >&2
      return 2
    fi
    if ((count > 0)); then printf '%s\t%s\t%s\n' "$start" "$count" "$path"; fi
  done <<<"$diff"
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

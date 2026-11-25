#!/usr/bin/env bash
set -uo pipefail

FILE_CAP=5

# shellcheck source=../../../lib/github-remote.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/github-remote.sh"

usage() {
  cat <<'EOF'
Extract typed reference edges from one repository's tracked files, one JSON object per line.
Usage: reference-edges.sh <repo-path> [--owner <owner>] [--print-owner]
  --owner <owner>  owner deciding internal vs external (default: the origin remote's owner)
  --print-owner    print the resolved owner and extract nothing
Exit: 0 edges emitted (possibly none); 1 the path is not a readable git repository; 2 usage.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

repo_arg=""
owner_override=""
print_owner=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --owner)
    shift
    [[ $# -gt 0 ]] || {
      printf 'reference-edges.sh: --owner needs a value\n' >&2
      exit 2
    }
    owner_override="$1"
    ;;
  --owner=*) owner_override="${1#--owner=}" ;;
  --print-owner) print_owner=1 ;;
  -*)
    printf 'reference-edges.sh: unknown option: %s\n' "$1" >&2
    exit 2
    ;;
  *)
    [[ -z "$repo_arg" ]] || {
      printf 'reference-edges.sh: one repository path only\n' >&2
      exit 2
    }
    repo_arg="$1"
    ;;
  esac
  shift
done

if [[ -z "$repo_arg" ]]; then
  printf 'usage: reference-edges.sh <repo-path> [--owner <owner>]\n' >&2
  exit 2
fi

if [[ ! -d "$repo_arg" ]]; then
  printf 'reference-edges.sh: not a directory: %s\n' "$repo_arg" >&2
  exit 1
fi

repo="$(cd "$repo_arg" 2>/dev/null && pwd)" || {
  printf 'reference-edges.sh: unreadable: %s\n' "$repo_arg" >&2
  exit 1
}
name="$(basename "$repo")"

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'reference-edges.sh: not a git repository, no tracked files to read: %s\n' "$repo" >&2
  exit 1
fi


origin="$(git -C "$repo" remote get-url origin 2>/dev/null)" || origin=""
origin="$(github_remote_path "$origin")" || origin=""

owner="$owner_override"
if [[ -z "$owner" && "$origin" == */* ]]; then
  owner="${origin%%/*}"
fi

self_slug=""
origin_owner="${origin%%/*}"
origin_repo="${origin#*/}"
origin_repo="${origin_repo%%/*}"
if [[ -n "$origin_owner" && -n "$origin_repo" && "$origin_owner" != "$origin" ]]; then
  self_slug="$origin_owner/$origin_repo"
fi

if [[ -n "$self_slug" ]]; then
  name="${self_slug#*/}"
fi

if [[ "$print_owner" -eq 1 ]]; then
  printf '%s\n' "${owner:-unknown}"
  exit 0
fi

is_reserved_owner() {
  case "$1" in
  sponsors | features | orgs | settings | apps | marketplace | topics | \
    collections | about | pricing | security | login | join | new | notifications | \
    explore | trending | events | site | contact | readme | pulls | issues | \
    codespaces | enterprise | customer-stories | organizations | user-attachments)
    return 0
    ;;
  *) return 1 ;;
  esac
}

is_valid_segment() {
  case "$1" in
  "" | . | ..) return 1 ;;
  *[!A-Za-z0-9_.-]*) return 1 ;;
  *) return 0 ;;
  esac
}

is_valid_owner() {
  is_valid_segment "$1" || return 1
  case "$1" in
  *.*) return 1 ;;
  *) return 0 ;;
  esac
}

is_placeholder_owner() {
  case "$1" in
  owner | org | user | username | your-org | your-owner | myorg | my-org | \
    example | example-org | acme | acme-corp | foo | bar | OWNER | ORG | USER | \
    other | eval-fixture)
    return 0
    ;;
  *) return 1 ;;
  esac
}


is_fixture_file() {
  case "$1" in
  *.test.* | *.spec.* | *.vectors.json) return 0 ;;
  test_*.py | */test_*.py | *_test.py | *_test.go) return 0 ;;
  */tests/* | tests/*) return 0 ;;
  */evals/* | evals/*) return 0 ;;
  */fixtures/* | fixtures/*) return 0 ;;
  */testdata/* | testdata/*) return 0 ;;
  *) is_own_artifact "$1" ;;
  esac
}

is_own_artifact() {
  case "${1##*/}" in
  landscape.json | landscape.md | landscape.dsl | landscape-notes.md | portfolio.md)
    return 0
    ;;
  *) return 1 ;;
  esac
}

is_self_reference() {
  local result=1 had_nocase=0
  [[ -n "$owner" || -n "$self_slug" ]] || return 1
  shopt -q nocasematch && had_nocase=1
  shopt -s nocasematch
  [[ -n "$owner" && "$1" == "$owner/$name" ]] && result=0
  [[ -n "$self_slug" && "$1" == "$self_slug" ]] && result=0
  [[ $had_nocase -eq 1 ]] || shopt -u nocasematch
  return "$result"
}

HITS=""
add_hit() {
  local target="$2" file="$3" o r
  is_fixture_file "$file" && return 0
  case "$target" in
  */*) ;;
  *) return 0 ;;
  esac
  o="${target%%/*}"
  r="${target#*/}"
  r="${r%%/*}"
  r="${r%%@*}"
  r="${r%.git}"
  while [[ "$r" == *. ]]; do r="${r%.}"; done
  is_valid_owner "$o" || return 0
  is_valid_segment "$r" || return 0
  is_reserved_owner "$o" && return 0
  is_placeholder_owner "$o" && return 0
  is_self_reference "$o/$r" && return 0
  HITS="$HITS$1	$o/$r	$file"$'\n'
}


grep_tracked() {
  local pattern="$1"
  shift
  git -C "$repo" grep -I -o -E -e "$pattern" -- "$@" 2>/dev/null
}

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  ref="${match#*uses:}"
  ref="${ref#"${ref%%[![:space:]]*}"}"
  case "$ref" in
  \"?*\")
    ref="${ref#\"}"
    ref="${ref%\"}"
    ;;
  \'?*\')
    ref="${ref#\'}"
    ref="${ref%\'}"
    ;;
  *) ;;
  esac
  case "$ref" in
  ./* | docker://*) continue ;;
  *) ;;
  esac
  add_hit uses-workflow "$ref" "$file"
done < <(grep_tracked '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^[:space:]]+' \
  '.github/workflows' '.github/actions' '*.yml' '*.yaml')

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  ref="${match##*[ \"]}"
  case "$ref" in
  ./* | ../* | /* | "") continue ;;
  *) ;;
  esac
  add_hit installs-plugin "$ref" "$file"
done < <(grep_tracked '(plugin marketplace add[[:space:]]+|"source"[[:space:]]*:[[:space:]]*")[A-Za-z0-9_./-]+' \
  '*.json' '*.md')

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  ref="${match#*github.com/}"
  add_hit depends-on "$ref" "$file"
done < <(grep_tracked '(^|[^A-Za-z0-9.-])github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' 'go.mod' '*/go.mod')

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  case "$file" in
  go.mod | */go.mod) continue ;;
  *) ;;
  esac
  ref="${match#*github.com/}"
  add_hit cites "$ref" "$file"
done < <(grep_tracked '(^|[^A-Za-z0-9.-])github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+')

if [[ -n "$owner" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    file="${line%%:*}"
    match="${line#*:}"
    ref="${match#*"$owner/"}"
    add_hit cites "$owner/$ref" "$file"
  done < <(grep_tracked "(^|[^A-Za-z0-9_./-])${owner}/[A-Za-z0-9_.-]+")
fi


[[ -n "$HITS" ]] || exit 0

printf '%s' "$HITS" | LC_ALL=C sort | awk -F'\t' \
  -v from="$name" -v owner="$owner" -v cap="$FILE_CAP" '
  function esc(s) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
    return s
  }
  function flush(  i, rel, out) {
    if (key == "") return
    rel = (owner != "" && curowner == owner) ? "internal" : "external"
    out = "{\"from\":\"" esc(from) "\",\"to\":\"" esc(curto) "\","
    out = out "\"type\":\"" esc(curtype) "\",\"relation\":\"" rel "\","
    out = out "\"count\":" count ",\"files\":["
    for (i = 1; i <= nfiles && i <= cap; i++) {
      if (i > 1) out = out ","
      out = out "\"" esc(files[i]) "\""
    }
    out = out "]}"
    print out
  }
  {
    k = $2 SUBSEP $1
    if (k != key) {
      flush()
      key = k; curtype = $1; curto = $2
      split(curto, parts, "/"); curowner = parts[1]
      count = 0; nfiles = 0; delete files; delete seen
    }
    count++
    if (!($3 in seen)) { seen[$3] = 1; files[++nfiles] = $3 }
  }
  END { flush() }
'

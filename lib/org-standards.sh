#!/usr/bin/env bash
set -euo pipefail

REPLACE_MARKER='<!-- review-base: replace -->'

die() { printf 'org-standards: %s\n' "$1" >&2; exit "${2:-2}"; }

cmd=${1:-}; shift || true
root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || die "--root needs a directory"; root=$2; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$cmd" in dir|index|review) ;; *) die "usage: org-standards.sh dir|index|review [--root DIR]" ;; esac
if [[ -z "$root" ]]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

yaml_value() {
  [[ -f "$1" ]] || return 0
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n 1 | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' \
    -e "s/^\"\(.*\)\"$/\1/" -e "s/^'\(.*\)'$/\1/"
}

org_dir() {
  if [[ -n "${STANDARDS_DIR:-}" ]]; then
    [[ -d "$STANDARDS_DIR" ]] || { printf 'org-standards: STANDARDS_DIR %s is not a directory\n' "$STANDARDS_DIR" >&2; return 4; }
    printf '%s\n' "$STANDARDS_DIR"; return 0
  fi
  local repo
  repo=$(yaml_value "$root/docs/conventions/source-control.yaml" standards_repository)
  [[ -n "$repo" ]] || return 3
  if ! [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]]; then
    printf 'org-standards: standards_repository %s is not <owner>/<repo>; no org layer\n' "$repo" >&2
    return 3
  fi
  local cache="${ORG_STANDARDS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-plugins/org-standards}/$repo"
  local stamp="$cache/.git/org-standards-fetched" ttl="${ORG_STANDARDS_TTL:-3600}" now
  local url="${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git"
  now=$(date +%s)
  if [[ -d "$cache/.git" ]]; then
    if [[ -f "$stamp" ]] && [[ $((now - $(cat "$stamp"))) -lt "$ttl" ]]; then
      printf '%s\n' "$cache"; return 0
    fi
    if git -C "$cache" fetch --quiet --depth=1 origin main 2>/dev/null \
      && git -C "$cache" checkout --quiet --force --detach FETCH_HEAD 2>/dev/null; then
      printf '%s\n' "$now" >"$stamp"
    else
      printf 'org-standards: refreshing %s failed; using the copy cached at %s\n' "$repo" "$cache" >&2
    fi
    printf '%s\n' "$cache"; return 0
  fi
  mkdir -p "$(dirname "$cache")"
  local tmp
  tmp=$(mktemp -d "$(dirname "$cache")/.clone.XXXXXX")
  if ! git clone --quiet --depth=1 --branch main "$url" "$tmp/c" 2>/dev/null; then
    rm -rf "${tmp:?}"
    printf 'org-standards: cannot clone %s; no org layer this run\n' "$url" >&2
    return 4
  fi
  printf '%s\n' "$now" >"$tmp/c/.git/org-standards-fetched"
  [[ -e "$cache" ]] || mv "$tmp/c" "$cache" 2>/dev/null || true
  rm -rf "${tmp:?}"
  printf '%s\n' "$cache"
}

first_line() { awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$1"; }

case "$cmd" in
  dir)
    org_dir ;;
  index)
    # shellcheck disable=SC2310  # org_dir's return code is the answer, not a failure
    org=$(org_dir) || exit $?
    dir=$(yaml_value "$org/.claude/standards.yaml" standards_dir)
    index="$org/${dir:-docs/standards}"; index="${index%/}/README.md"
    if [[ -f "$index" ]] && awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit 1 } /^standards-contract:/ { found = 1; exit } END { exit !found }' "$index"; then
      printf '%s\n' "$index"
    else
      printf 'org-standards: %s has no standards index\n' "$org" >&2; exit 5
    fi ;;
  review)
    local_file="$root/REVIEW.md"
    first=""
    [[ -f "$local_file" ]] && first=$(first_line "$local_file")
    if [[ "$first" = "$REPLACE_MARKER" ]]; then
      cat "$local_file"; exit 0
    fi
    status=0
    # shellcheck disable=SC2310  # org_dir's return code is the answer, not a failure
    org=$(org_dir) || status=$?
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 3 ]] || [[ "$status" -eq 4 ]] || exit "$status"
    if [[ "$status" -eq 0 ]] && [[ -f "$org/REVIEW.md" ]]; then
      cat "$org/REVIEW.md"
      if [[ -f "$local_file" ]] && ! cmp -s "$org/REVIEW.md" "$local_file"; then
        printf '\n<!-- The repository REVIEW.md follows: its criteria add to the organization criteria above. -->\n\n'
        cat "$local_file"
      fi
    elif [[ -f "$local_file" ]]; then
      cat "$local_file"
    else
      exit 3
    fi ;;
  *)
    die "unknown command: $cmd" ;;
esac

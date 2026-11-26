#!/usr/bin/env bash
# Exit codes:
#   0  ran successfully (--list/--list0/--probe always exit 0, findings or not;
#      --fix exits 0 when every offending path was fixed)
#   2  usage error
#   3  not a git repository, or git unavailable
#   4  --fix failed on at least one path
set -uo pipefail

PROG=${0##*/}

usage() {
  cat >&2 <<EOF
$PROG — deterministic exec-bit backstop for /source-control:commit.

Usage:
  $PROG [--list | --list0 | --probe | --fix] [--repo-dir <dir>] [--all] [-- <path>...]

Modes (default --list):
  --list             One offending path per line. Empty output = nothing to do.
                     A path containing a newline is shell-quoted (%q) to keep
                     one record per line; use --list0 for full unambiguity.
  --list0            NUL-delimited paths — the unambiguous machine-readable form.
  --probe            Single-line summary for pre-computed skill context.
  --fix              chmod +x the worktree file, then git update-index --chmod=+x.
                     Requires an explicit scope: '-- <path>...' or --all.

Options:
  --repo-dir <dir>   Operate on this repository instead of the current directory.
  --all              Allow --fix to sweep the whole staged set (explicit opt-in).
  -- <path>...       Limit to these pathspecs (default for --list/--probe: whole staged set).
  -h, --help         This help.

Reports paths staged at a NEW index entry whose staged blob starts with '#!' but
whose staged mode is 100644. A new entry is not just status 'A': a copy
destination counts, as does a rename destination whose source was 100755.
Symlinks and already-executable entries are skipped.

Scope note: a rename off a 100644 source is deliberately NOT reported, so for
that one case the answer depends on your diff.renames setting (reported as an
add when off, skipped as a rename when on). Decided trade — see
reference/exec-bit.md.
EOF
}

die() {
  echo "$PROG: $2" >&2
  exit "$1"
}

print_path() {
  case "$1" in
  *$'\n'*) printf '%q' "$1" ;;
  *) printf '%s' "$1" ;;
  esac
}

mode=list
repo_dir=""
all=0
paths=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --list | --list0 | --probe | --fix) mode=${1#--} ;;
  --all) all=1 ;;
  --repo-dir)
    [[ "$#" -ge 2 ]] || die 2 "--repo-dir needs a value"
    repo_dir="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    paths+=("$@")
    break
    ;;
  *)
    echo "$PROG: unknown argument '$1'" >&2
    usage
    exit 2
    ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || die 3 "git not found on PATH"

if [[ -n "$repo_dir" ]]; then
  cd -- "$repo_dir" 2>/dev/null || die 3 "cannot enter --repo-dir '$repo_dir'"
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 3 "not inside a git work tree"

repo_prefix="$(git rev-parse --show-prefix 2>/dev/null)"
repo_top="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -n "$repo_prefix" ]] && [[ "${#paths[@]}" -gt 0 ]]; then
  for i in "${!paths[@]}"; do
    case "${paths[i]}" in
    /* | :*) ;;
    *) paths[i]="$repo_prefix${paths[i]}" ;;
    esac
  done
fi
if [[ -n "$repo_top" ]]; then
  cd -- "$repo_top" 2>/dev/null || die 3 "cannot enter repository root '$repo_top'"
fi

if [[ "$mode" == "fix" ]] && [[ "$all" -eq 0 ]] && [[ "${#paths[@]}" -eq 0 ]]; then
  echo "$PROG: --fix needs an explicit scope: pass '-- <path>...' for this commit's paths," >&2
  echo "       or --all to deliberately sweep the whole staged set." >&2
  exit 2
fi

added=()
while IFS= read -r -d '' info; do
  info="${info#:}"
  src_mode="${info%% *}"
  status="${info##* }"
  case "$status" in
  R*)
    IFS= read -r -d '' _source || break
    IFS= read -r -d '' path || break
    [[ "$src_mode" == "100755" ]] && added+=("$path")
    ;;
  C*)
    IFS= read -r -d '' _source || break
    IFS= read -r -d '' path || break
    added+=("$path")
    ;;
  A)
    IFS= read -r -d '' path || break
    added+=("$path")
    ;;
  *)
    IFS= read -r -d '' _path || break
    ;;
  esac
done < <(git diff --cached --raw -z -- ${paths[@]+"${paths[@]}"} 2>/dev/null)

offenders=()
for path in ${added+"${added[@]}"}; do
  read -r entry_mode blob_sha _ < <(git ls-files --stage -- "$path" 2>/dev/null | head -n 1) || continue
  [[ "$entry_mode" == "100644" ]] || continue
  [[ "$(git cat-file blob "$blob_sha" 2>/dev/null | head -c 2)" == "#!" ]] || continue
  offenders+=("$path")
done

count=${#offenders[@]}

case "$mode" in
list)
  for path in ${offenders+"${offenders[@]}"}; do
    print_path "$path"
    printf '\n'
  done
  ;;
list0)
  for path in ${offenders+"${offenders[@]}"}; do
    printf '%s\0' "$path"
  done
  ;;
probe)
  if [[ "$count" -eq 0 ]]; then
    printf 'none\n'
  else
    printf '%s staged shebang file(s) still at mode 100644:' "$count"
    for path in "${offenders[@]}"; do
      printf ' '
      print_path "$path"
    done
    printf '\n'
  fi
  ;;
fix)
  if [[ "$count" -eq 0 ]]; then
    printf 'exec-bit-check: nothing to fix\n'
    exit 0
  fi
  failed=0
  for path in "${offenders[@]}"; do
    if [[ -L "$path" ]]; then
      echo "$PROG: refusing '$path': staged as a regular file but the worktree entry is a symlink" >&2
      failed=1
      continue
    elif [[ -e "$path" ]]; then
      chmod +x -- "$path" 2>/dev/null || {
        echo "$PROG: chmod +x failed for '$path'" >&2
        failed=1
        continue
      }
    else
      echo "$PROG: warning: '$path' is staged but absent from the worktree; fixing the index entry only" >&2
    fi
    git update-index --chmod=+x -- "$path" 2>/dev/null || {
      echo "$PROG: git update-index --chmod=+x failed for '$path'" >&2
      failed=1
      continue
    }
    printf 'exec-bit-check: fixed %s\n' "$path"
  done
  [[ "$failed" -eq 0 ]] || exit 4
  ;;
*) die 2 "internal error: unhandled mode '$mode'" ;;
esac
exit 0

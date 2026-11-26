#!/usr/bin/env bash
# Exit codes:
#   0  copy/sync-back succeeded; diff found no differences (or no .worktreeinclude)
#   1  diff found one or more differences
#   2  usage error, or sync-back rejected a path outside the intersection
#   3  fail-closed unreadable (missing/unreadable worktree, main root, .worktreeinclude,
#      git failure, or file read/compare failure)
#   4  copy failed for one or more files

set -uo pipefail

PROG=${0##*/}

usage() {
  cat >&2 <<EOF
Usage:
  $PROG copy --from <main-root> --to <worktree>
  $PROG diff [<worktree>] [--main-root <dir>] [--worktree-only] [--unified]
  $PROG sync-back <worktree> [--main-root <dir>] [--copy <rel>]... [--remove <rel>]...
EOF
  exit 2
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "${2:-2}"
}

canon_dir() {
  local d="$1"
  [[ -d "$d" && -r "$d" ]] || return 1
  (CDPATH='' cd -P -- "$d" 2>/dev/null && pwd)
}

resolve_toplevel() {
  local d="$1" top
  [[ -d "$d" && -r "$d" ]] || return 1
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="${top%$'\r'}"
  [[ -n "$top" ]] || return 1
  canon_dir "$top"
}

resolve_main_root() {
  local wt_top="$1" given="${2:-}" common main_dir
  if [[ -n "$given" ]]; then
    resolve_toplevel "$given" || return 1
    return 0
  fi
  common="$(git -C "$wt_top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  common="${common%$'\r'}"
  [[ -n "$common" ]] || return 1
  if [[ "${common##*/}" == ".git" ]]; then
    main_dir="${common%/.git}"
  else
    main_dir="$common"
  fi
  canon_dir "$main_dir"
}

resolve_include_file() {
  local main_root="$1" wt_top="${2:-}"
  if [[ -e "$main_root/.worktreeinclude" ]]; then
    [[ -f "$main_root/.worktreeinclude" && -r "$main_root/.worktreeinclude" ]] || return 3
    printf '%s' "$main_root/.worktreeinclude"
    return 0
  fi
  if [[ -n "$wt_top" && -e "$wt_top/.worktreeinclude" ]]; then
    [[ -f "$wt_top/.worktreeinclude" && -r "$wt_top/.worktreeinclude" ]] || return 3
    printf '%s' "$wt_top/.worktreeinclude"
    return 0
  fi
  return 1
}

collect_included() {
  local dir="$1" inc="$2" out="$3" raw rc=0
  [[ -d "$dir" && -r "$dir" ]] || return 3
  [[ -f "$inc" && -r "$inc" ]] || return 3
  raw="$(mktemp)" || return 3
  if ! git -C "$dir" ls-files -o -i -z --exclude-from="$inc" >"$raw" 2>/dev/null; then
    rm -f "$raw"
    return 3
  fi
  : >"$out"
  if [[ -s "$raw" ]]; then
    git -C "$dir" check-ignore --stdin -z <"$raw" >"$out" 2>/dev/null
    rc=$?
    if ((rc != 0 && rc != 1)); then
      rm -f "$raw"
      return 3
    fi
  fi
  rm -f "$raw"
  return 0
}

valid_rel_path() {
  local p="$1"
  [[ -n "$p" ]] || return 1
  [[ "$p" != /* && ! "$p" =~ ^[A-Za-z]:/ && "$p" != *\\* ]] || return 1
  [[ "$p" != *$'\t'* && "$p" != *$'\n'* && "$p" != *$'\r'* ]] || return 1
  [[ "$p" != "." && "$p" != ".." && "$p" != ./* && "$p" != ../* && "$p" != */. && "$p" != */.. && "$p" != */./* && "$p" != */../* && "$p" != *//* ]] || return 1
  return 0
}

do_copy() {
  local from_dir="" to_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --from)
      [[ $# -ge 2 ]] || usage
      from_dir="$2"
      shift 2
      ;;
    --to)
      [[ $# -ge 2 ]] || usage
      to_dir="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) die "copy: unknown argument: $1" 2 ;;
    esac
  done
  [[ -n "$from_dir" && -n "$to_dir" ]] || die "copy requires --from <main-root> and --to <worktree>" 2

  local main_root wt_dir inc
  main_root="$(resolve_toplevel "$from_dir")" || die "copy: unreadable source repository: $from_dir" 3
  wt_dir="$(canon_dir "$to_dir")" || die "copy: unreadable destination worktree: $to_dir" 3

  inc=""
  local rc=0
  inc="$(resolve_include_file "$main_root")" || rc=$?
  if ((rc == 3)); then
    die "copy: unreadable .worktreeinclude in $main_root" 3
  elif ((rc != 0)); then
    printf '0\n'
    return 0
  fi

  local list_file
  list_file="$(mktemp)" || die "copy: cannot create temp file" 3
  # shellcheck disable=SC2064
  trap "rm -f '$list_file'" RETURN
  collect_included "$main_root" "$inc" "$list_file" || die "copy: failed to enumerate .worktreeinclude files in $main_root" 3

  local rel src dest copied=0 failed=0
  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] || continue
    src="$main_root/$rel"
    [[ -f "$src" && ! -L "$src" ]] || continue
    has_no_symlink_components "$main_root" "$rel" || continue
    dest="$wt_dir/$rel"
    if ! has_no_symlink_components "$wt_dir" "$rel" || { [[ -e "$dest" ]] && [[ ! -f "$dest" || -L "$dest" ]]; }; then
      failed=$((failed + 1))
      printf '%s: warning: refusing symlink or non-regular destination for .worktreeinclude file: %s\n' "$PROG" "$rel" >&2
      continue
    fi
    if mkdir -p "$(dirname "$dest")" && cp -p -- "$src" "$dest"; then
      copied=$((copied + 1))
    else
      failed=$((failed + 1))
      printf '%s: warning: failed to copy .worktreeinclude file: %s\n' "$PROG" "$rel" >&2
    fi
  done <"$list_file"

  printf '%d\n' "$copied"
  if ((failed > 0)); then
    printf '%s: %d .worktreeinclude file(s) failed to copy into %s\n' "$PROG" "$failed" "$wt_dir" >&2
    return 4
  fi
  return 0
}

do_diff() {
  local wt_arg="" main_arg="" worktree_only=0 unified=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --main-root)
      [[ $# -ge 2 ]] || usage
      main_arg="$2"
      shift 2
      ;;
    --worktree-only)
      worktree_only=1
      shift
      ;;
    --unified)
      unified=1
      shift
      ;;
    -h | --help) usage ;;
    --)
      shift
      break
      ;;
    -*) die "diff: unknown argument: $1" 2 ;;
    *)
      [[ -z "$wt_arg" ]] || die "diff: unexpected argument: $1" 2
      wt_arg="$1"
      shift
      ;;
    esac
  done
  [[ -n "$wt_arg" ]] || wt_arg="."

  local wt_top main_root inc rc=0
  wt_top="$(resolve_toplevel "$wt_arg")" || die "diff: unreadable worktree: $wt_arg" 3
  main_root="$(resolve_main_root "$wt_top" "$main_arg")" || die "diff: unreadable main root for $wt_top" 3
  if [[ "$wt_top" == "$main_root" ]]; then
    return 0
  fi

  inc=""
  rc=0
  inc="$(resolve_include_file "$main_root" "$wt_top")" || rc=$?
  if ((rc == 3)); then
    die "diff: unreadable .worktreeinclude" 3
  elif ((rc != 0)); then
    return 0
  fi

  local wt_list main_list
  wt_list="$(mktemp)" || die "diff: cannot create temp file" 3
  main_list="$(mktemp)" || {
    rm -f "$wt_list"
    die "diff: cannot create temp file" 3
  }
  # shellcheck disable=SC2064
  trap "rm -f '$wt_list' '$main_list'" RETURN

  collect_included "$wt_top" "$inc" "$wt_list" || die "diff: failed to inspect worktree $wt_top" 3
  if ((worktree_only == 0)); then
    collect_included "$main_root" "$inc" "$main_list" || die "diff: failed to inspect main root $main_root" 3
  fi

  local -A wt_seen=()
  local -a diff_status=() diff_rel=()
  local rel cmp_rc

  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] || continue
    wt_seen["$rel"]=1
    if [[ "$rel" == *$'\t'* || "$rel" == *$'\n'* ]]; then
      die "diff: carried file path holds a tab or newline: $rel" 3
    fi
    if [[ ! -f "$wt_top/$rel" ]]; then
      continue
    fi
    [[ -r "$wt_top/$rel" ]] || die "diff: unreadable worktree file: $wt_top/$rel" 3
    if [[ -e "$main_root/$rel" ]]; then
      [[ -f "$main_root/$rel" && -r "$main_root/$rel" ]] || die "diff: unreadable main file: $main_root/$rel" 3
      cmp -s -- "$wt_top/$rel" "$main_root/$rel"
      cmp_rc=$?
      if ((cmp_rc == 1)); then
        diff_status+=("MODIFIED")
        diff_rel+=("$rel")
      elif ((cmp_rc > 1)); then
        die "diff: failed comparing $rel" 3
      fi
    else
      diff_status+=("NEW")
      diff_rel+=("$rel")
    fi
  done <"$wt_list"

  if ((worktree_only == 0)); then
    while IFS= read -r -d '' rel; do
      [[ -n "$rel" ]] || continue
      if [[ -n "${wt_seen[$rel]+x}" || -e "$wt_top/$rel" ]]; then
        continue
      fi
      if [[ "$rel" == *$'\t'* || "$rel" == *$'\n'* ]]; then
        die "diff: carried file path holds a tab or newline: $rel" 3
      fi
      [[ -f "$main_root/$rel" ]] || continue
      [[ -r "$main_root/$rel" ]] || die "diff: unreadable main file: $main_root/$rel" 3
      diff_status+=("ABSENT")
      diff_rel+=("$rel")
    done <"$main_list"
  fi

  ((${#diff_rel[@]} > 0)) || return 0

  local i st d_rc
  for i in "${!diff_rel[@]}"; do
    st="${diff_status[$i]}"
    rel="${diff_rel[$i]}"
    if ((unified)); then
      case "$st" in
      MODIFIED)
        diff -u -- "$main_root/$rel" "$wt_top/$rel"
        d_rc=$?
        ;;
      NEW)
        diff -u -- /dev/null "$wt_top/$rel"
        d_rc=$?
        ;;
      ABSENT)
        diff -u -- "$main_root/$rel" /dev/null
        d_rc=$?
        ;;
      *) d_rc=2 ;;
      esac
      if ((d_rc > 1)); then
        die "diff: unified diff failed for $rel" 3
      fi
    else
      printf '%s\t%s\t%s\n' "$st" "$rel" "$main_root/$rel"
    fi
  done
  return 1
}

has_no_symlink_components() {
  local cur="$1" rel="$2" seg
  local -a parts=()
  IFS='/' read -r -a parts <<<"$rel"
  for seg in "${parts[@]}"; do
    [[ -n "$seg" ]] || continue
    cur="$cur/$seg"
    [[ ! -L "$cur" ]] || return 1
  done
  return 0
}

do_sync_back() {
  local wt_arg="" main_arg=""
  local -a to_copy=() to_remove=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --main-root)
      [[ $# -ge 2 ]] || usage
      main_arg="$2"
      shift 2
      ;;
    --copy)
      [[ $# -ge 2 ]] || usage
      to_copy+=("$2")
      shift 2
      ;;
    --remove)
      [[ $# -ge 2 ]] || usage
      to_remove+=("$2")
      shift 2
      ;;
    -h | --help) usage ;;
    --)
      shift
      break
      ;;
    -*) die "sync-back: unknown argument: $1" 2 ;;
    *)
      [[ -z "$wt_arg" ]] || die "sync-back: unexpected argument: $1" 2
      wt_arg="$1"
      shift
      ;;
    esac
  done
  [[ -n "$wt_arg" ]] || die "sync-back requires a <worktree> path" 2
  ((${#to_copy[@]} + ${#to_remove[@]} > 0)) || die "sync-back requires at least one --copy or --remove path" 2

  local wt_top main_root inc rc=0
  wt_top="$(resolve_toplevel "$wt_arg")" || die "sync-back: unreadable worktree: $wt_arg" 3
  main_root="$(resolve_main_root "$wt_top" "$main_arg")" || die "sync-back: unreadable main root for $wt_top" 3
  [[ "$wt_top" != "$main_root" ]] || die "sync-back: worktree and main root are the same directory: $wt_top" 2

  inc=""
  rc=0
  inc="$(resolve_include_file "$main_root" "$wt_top")" || rc=$?
  if ((rc == 3)); then
    die "sync-back: unreadable .worktreeinclude" 3
  elif ((rc != 0)); then
    die "sync-back: no .worktreeinclude found; refusing to copy or remove any path" 2
  fi

  local wt_list main_list
  wt_list="$(mktemp)" || die "sync-back: cannot create temp file" 3
  main_list="$(mktemp)" || {
    rm -f "$wt_list"
    die "sync-back: cannot create temp file" 3
  }
  # shellcheck disable=SC2064
  trap "rm -f '$wt_list' '$main_list'" RETURN

  collect_included "$wt_top" "$inc" "$wt_list" || die "sync-back: failed to inspect worktree $wt_top" 3
  collect_included "$main_root" "$inc" "$main_list" || die "sync-back: failed to inspect main root $main_root" 3

  local -A wt_allowed=() main_allowed=()
  local rel
  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] && wt_allowed["$rel"]=1
  done <"$wt_list"
  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] && main_allowed["$rel"]=1
  done <"$main_list"

  for rel in ${to_copy[@]+"${to_copy[@]}"}; do
    valid_rel_path "$rel" || die "sync-back: invalid path for --copy: $rel" 2
    [[ -n "${wt_allowed[$rel]+x}" ]] || die "sync-back: path outside .worktreeinclude intersection for --copy: $rel" 2
    has_no_symlink_components "$wt_top" "$rel" || die "sync-back: --copy source crosses a symlink: $wt_top/$rel" 2
    [[ -f "$wt_top/$rel" && ! -L "$wt_top/$rel" ]] || die "sync-back: --copy source is not a regular file: $wt_top/$rel" 2
    has_no_symlink_components "$main_root" "$rel" || die "sync-back: --copy destination crosses a symlink: $main_root/$rel" 2
    if [[ -e "$main_root/$rel" && ! -f "$main_root/$rel" ]]; then
      die "sync-back: --copy destination is not a regular file: $main_root/$rel" 2
    fi
  done
  for rel in ${to_remove[@]+"${to_remove[@]}"}; do
    valid_rel_path "$rel" || die "sync-back: invalid path for --remove: $rel" 2
    [[ -n "${main_allowed[$rel]+x}" ]] || die "sync-back: path outside .worktreeinclude intersection for --remove: $rel" 2
    has_no_symlink_components "$main_root" "$rel" || die "sync-back: --remove target crosses a symlink: $main_root/$rel" 2
    [[ -f "$main_root/$rel" && ! -L "$main_root/$rel" ]] || die "sync-back: --remove target is not a regular file: $main_root/$rel" 2
  done

  for rel in ${to_copy[@]+"${to_copy[@]}"}; do
    if ! mkdir -p "$(dirname "$main_root/$rel")" || ! cp -p -- "$wt_top/$rel" "$main_root/$rel"; then
      die "sync-back: failed to copy $rel to $main_root" 3
    fi
    printf 'copied\t%s\t%s\n' "$rel" "$main_root/$rel"
  done
  for rel in ${to_remove[@]+"${to_remove[@]}"}; do
    rm -f -- "$main_root/$rel" || die "sync-back: failed to remove $main_root/$rel" 3
    printf 'removed\t%s\t%s\n' "$rel" "$main_root/$rel"
  done
  return 0
}

cmd="${1:-}"
case "$cmd" in
copy)
  shift
  do_copy "$@"
  ;;
diff)
  shift
  do_diff "$@"
  ;;
sync-back)
  shift
  do_sync_back "$@"
  ;;
-h | --help | "")
  usage
  ;;
*)
  die "unknown verb: $cmd" 2
  ;;
esac

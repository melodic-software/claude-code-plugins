#!/usr/bin/env bash
set -uo pipefail

PROG=${0##*/}

# shellcheck source=worktree-root-resolve.sh
source "${BASH_SOURCE[0]%/*}/worktree-root-resolve.sh"
# shellcheck source=lib/worktree-facts.sh
source "${BASH_SOURCE[0]%/*}/lib/worktree-facts.sh" || {
  printf '%s: cannot load lib/worktree-facts.sh\n' "$PROG" >&2
  exit 2
}

repo_dir="."
while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo-dir)
    if [[ $# -lt 2 ]]; then
      printf '%s: --repo-dir requires a value\n' "$PROG" >&2
      exit 2
    fi
    repo_dir="$2"
    shift 2
    ;;
  -h | --help)
    cat <<'EOF'
worktree-root-doctor.sh: check the worktreeroot.path convention and name which rule supplied the root.

Usage:
  worktree-root-doctor.sh [--repo-dir <dir>]

  --repo-dir  the repository to check (default: the current directory)

Output: one finding per line, `ok:` / `info:` / `warn:` / `error:`.

Exit codes:
  0  no warnings or errors
  1  at least one warn/error finding
  2  usage error
EOF
    exit 0
    ;;
  *)
    printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2
    exit 2
    ;;
  esac
done

FINDINGS=0

ok() { printf 'ok: %s\n' "$1"; }
note() { printf 'info: %s\n' "$1"; }
warn() {
  printf 'warn: %s\n' "$1"
  FINDINGS=$((FINDINGS + 1))
}
err() {
  printf 'error: %s\n' "$1"
  FINDINGS=$((FINDINGS + 1))
}

expand_tilde() {
  local p="$1"
  # Config values arrive verbatim, so matching the literal unexpanded tilde is the point.
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    printf '%s/%s' "${HOME%/}" "${p#\~/}"
  else
    printf '%s' "$p"
  fi
}

canon() {
  local r
  if r=$(realpath -- "$1" 2>/dev/null) || r=$(readlink -f -- "$1" 2>/dev/null); then
    [[ -n "$r" ]] && {
      printf '%s' "$r"
      return 0
    }
  fi
  printf '%s' "$1"
}

if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
  err "repository unreadable at $repo_dir — not a git repository, or dubious ownership (safe.directory). Until this resolves, any 'git -C <here> config --get worktreeroot.path' silently returns the GLOBAL value as if it were this repository's answer (rc=0, no stderr). Fix: run from a repository, or 'git config --global --add safe.directory <path>'."
  exit 1
fi

git_dir=$(git -C "$repo_dir" rev-parse --absolute-git-dir 2>/dev/null | tr -d '\r')
common_dir=$(git -C "$repo_dir" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')
if [[ -n "$common_dir" && "$common_dir" != /* && ! "$common_dir" =~ ^[A-Za-z]:/ ]]; then
  common_dir="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')/$common_dir"
fi
if [[ -n "$git_dir" && -n "$common_dir" && "$(canon "$git_dir")" != "$(canon "$common_dir")" ]]; then
  note "linked worktree: gitdir is $git_dir (under the main repository), so gitdir-anchored includeIf conditions classify this worktree WITH its repository — and a pattern anchored at this worktree's own tree path matches nothing, ever."
fi

declare -a inc_conds=() inc_paths=() inc_origins=() inc_resolved=()
declare -A contributing_origin=()

while IFS= read -r -d '' origin && IFS= read -r -d '' kv; do
  if [[ "$kv" == *$'\n'* ]]; then
    key="${kv%%$'\n'*}"
    val="${kv#*$'\n'}"
  else
    key="$kv"
    val=""
  fi
  ofile=""
  [[ "$origin" == file:* ]] && ofile="${origin#file:}"
  [[ -n "$ofile" ]] && contributing_origin["$(canon "$ofile")"]=1
  if [[ "$key" == includeif.*.path ]]; then
    cond="${key#includeif.}"
    cond="${cond%.path}"
    inc_conds+=("$cond")
    inc_paths+=("$val")
    inc_origins+=("$ofile")
    rp="$(expand_tilde "$val")"
    if [[ "$rp" != /* && ! "$rp" =~ ^[A-Za-z]:/ && -n "$ofile" ]]; then
      rp="$(dirname "$ofile")/$rp"
    fi
    inc_resolved+=("$(canon "$rp")")
  fi
done < <(git -C "$repo_dir" config --list --show-origin -z 2>/dev/null | tr -d '\r')

git_version_num=0
if [[ "$(git --version 2>/dev/null)" =~ ([0-9]+)\.([0-9]+) ]]; then
  git_version_num=$((BASH_REMATCH[1] * 100 + BASH_REMATCH[2]))
fi

is_include_file() {
  local c k
  c="$(canon "$1")"
  for k in ${inc_resolved[@]+"${inc_resolved[@]}"}; do
    [[ "$k" == "$c" ]] && return 0
  done
  return 1
}

for idx in ${inc_conds[@]+"${!inc_conds[@]}"}; do
  cond="${inc_conds[idx]}"
  resolved="${inc_resolved[idx]}"
  fired="did not contribute values here"
  [[ -n "${contributing_origin["$resolved"]:-}" ]] && fired="target file contributed values here"
  note "includeIf \"$cond\" -> ${inc_paths[idx]} — $fired"

  if [[ ! -f "$resolved" ]]; then
    warn "includeIf \"$cond\" points at a nonexistent file ($resolved) — git skips it silently (rc=0, no stderr), so this condition can never fire"
  fi
  case "$cond" in
  gitdir:*)
    case "${OSTYPE:-}" in
    msys* | cygwin* | win32)
      warn "includeIf \"$cond\" uses case-sensitive gitdir: on a Windows shell — a lowercase drive letter, 8.3 short name, or casing differing from the canonical gitdir matches nothing (only the pattern author's spelling matters). Use gitdir/i: on Windows."
      ;;
    *) ;;
    esac
    ;;
  gitdir/i:* | onbranch:*) ;;
  hasconfig:remote.*.url:*)
    note "includeIf \"$cond\": hasconfig: is unimplemented in libgit2 (gitui, TortoiseGit, git2/nodegit/pygit2 bindings), where unrecognized conditions fail silently, and JGit/go-git resolve no includeIf at all — fine for melodic.* (CLI-shelling readers only), unsafe as the identity layer (user.email etc.). Use gitdir/i: for identity."
    ;;
  worktree:* | worktree/i:*)
    if ((git_version_num < 256)); then
      warn "includeIf \"$cond\" needs git >= 2.56; this machine's git skips it silently (rc=0, no stderr) — the condition never fires here"
    fi
    ;;
  *)
    warn "includeIf \"$cond\" is not a keyword this git recognizes (gitdir:, gitdir/i:, onbranch:, hasconfig:remote.*.url:, worktree:, worktree/i:) — unknown keywords are skipped silently, so a typo here is indistinguishable from an unset key"
    ;;
  esac
  case "$cond" in
  gitdir:*/.git | gitdir/i:*/.git)
    note "includeIf \"$cond\" ends in /.git — a bare repository's gitdir has no /.git suffix, so this pattern silently misses bare clones"
    ;;
  *) ;;
  esac
done

declare -a val_origins=() val_values=()
winning_key=""
root_expanded=""
if worktree_root_resolve "$repo_dir"; then
  winning_key="$WORKTREE_ROOT_KEY_USED"
  while IFS= read -r -d '' origin && IFS= read -r -d '' val; do
    ofile=""
    [[ "$origin" == file:* ]] && ofile="${origin#file:}"
    val_origins+=("$ofile")
    val_values+=("$val")
  done < <(git -C "$repo_dir" config --show-origin -z --get-all --type=path "$winning_key" 2>/dev/null | tr -d '\r')
fi

nvals=${#val_values[@]}
if ((nvals == 0)) || [[ -z "$winning_key" ]]; then
  note "worktreeroot.path is unset — the creation helper falls through to the worktree_root plugin option, then the plugin data directory. Set the key so every consumer can read the root: git config --global worktreeroot.path <dir-outside-every-repo>."
else
  win_idx=$((nvals - 1))
  win_val="${val_values[win_idx]}"
  win_origin="${val_origins[win_idx]}"
  supplied_by="$win_origin"
  win_from_include=0
  win_origin_canon="$(canon "$win_origin")"
  for idx in ${inc_resolved[@]+"${!inc_resolved[@]}"}; do
    if [[ "${inc_resolved[idx]}" == "$win_origin_canon" ]]; then
      supplied_by="includeIf \"${inc_conds[idx]}\" via $win_origin"
      win_from_include=1
      break
    fi
  done
  ok "$winning_key = $win_val (supplied by $supplied_by)"

  if ((nvals > 1)); then
    losing_include=0
    for ((idx = 0; idx < win_idx; idx++)); do
      # shellcheck disable=SC2310  # pure predicate; both branches are handled
      if is_include_file "${val_origins[idx]}"; then
        losing_include=1
        break
      fi
    done
    if ((losing_include && !win_from_include)); then
      warn "a plain $winning_key in $win_origin is parsed AFTER an include-supplied value and silently overrides it — precedence is parse order, not specificity. If the include is meant to win, move the plain default ABOVE the includeIf block."
    elif ((win_from_include)); then
      note "several values are set ($nvals); last parsed wins, and the winner comes from an include — the layering is working"
    fi
  fi

  scoped_val="$(git config --global --get --type=path "$winning_key" 2>/dev/null | tail -n 1 | tr -d '\r')"
  if [[ "$scoped_val" != "$win_val" ]]; then
    note "a scoped read ('git config --global --get $winning_key', includes OFF by default when a scope flag is given) returns '${scoped_val:-<nothing>}' here, not '$win_val' — consumers must never pass a scope flag without --includes"
  fi

  root_expanded="$(expand_tilde "$win_val")"
  if [[ -e "$root_expanded" ]] && git -C "$root_expanded" rev-parse --show-toplevel >/dev/null 2>&1; then
    warn "the resolved root $win_val sits INSIDE a git working tree — the one placement the convention exists to prevent; point it at a directory outside every repository"
  fi
fi

common_of() {
  local c
  c=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null | tr -d '\r') || return 1
  [[ -n "$c" ]] || return 1
  if [[ "$c" != /* && ! "$c" =~ ^[A-Za-z]:/ ]]; then
    c="$1/$c"
  fi
  canon "$c"
}

own_common="$(canon "$common_dir")"
nested_porcelain="$(mktemp)" || nested_porcelain=""
if [[ -n "$nested_porcelain" ]] && git -C "$repo_dir" worktree list --porcelain -z >"$nested_porcelain" 2>/dev/null; then
  worktree_facts_parse_z "$nested_porcelain"
  owner_main="${WT_FACT_PATH[0]:-$repo_dir}"
  root_canon=""
  [[ -n "$root_expanded" ]] && root_canon="$(canon "$root_expanded")"
  for wt_idx in ${WT_FACT_PATH[@]+"${!WT_FACT_PATH[@]}"}; do
    [[ "${WT_FACT_LINKED[wt_idx]}" == "yes" ]] || continue
    wt_path="${WT_FACT_PATH[wt_idx]}"
    wt_canon="$(canon "$wt_path")"
    if [[ -n "$root_canon" && "$wt_canon" == "$root_canon"/* ]]; then
      continue
    fi
    ancestor="$(dirname -- "$wt_canon")"
    while [[ -d "$ancestor" && -r "$ancestor" && -x "$ancestor" ]]; do
      if [[ -e "$ancestor/.git" ]]; then
        ancestor_common="$(common_of "$ancestor")" || ancestor_common=""
        [[ "$ancestor_common" == "$own_common" ]] && break
        if [[ -n "$ancestor_common" ]]; then
          err "worktree $wt_path of repository $owner_main sits inside the work tree of a different repository ($ancestor). Remove it: git -C $owner_main worktree remove $wt_path"
          break
        fi
      fi
      parent="$(dirname -- "$ancestor")"
      [[ "$parent" != "$ancestor" ]] || break
      ancestor="$parent"
    done
  done
fi
[[ -z "$nested_porcelain" ]] || rm -f "$nested_porcelain"

signing_configured="$(git -C "$repo_dir" config --get user.signingkey 2>/dev/null | tr -d '\r')"
for idx in ${inc_resolved[@]+"${!inc_resolved[@]}"}; do
  f="${inc_resolved[idx]}"
  [[ -f "$f" ]] || continue
  inc_email="$(git config --file "$f" --get user.email 2>/dev/null | tr -d '\r')"
  [[ -n "$inc_email" ]] || continue
  inc_key="$(git config --file "$f" --get user.signingkey 2>/dev/null | tr -d '\r')"
  if [[ -n "$signing_configured" && -z "$inc_key" ]]; then
    warn "identity include ${inc_paths[idx]} sets user.email but not user.signingkey while a signing key is configured elsewhere — the other identity's key signs these commits, verifies Good locally (%G? never compares signer to author), and shows Unverified only on the forge. Set the signing/transport keys inside each identity file."
  fi
done

note "not machine-checked here: NTFS junction-anchored gitdir patterns match nothing in either direction (anchor at canonical targets), and --show-scope collapses include-supplied values to 'global' (use --show-origin, as this doctor does)"

((FINDINGS == 0)) || exit 1
exit 0

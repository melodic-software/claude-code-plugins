#!/usr/bin/env bash
# worktree-root-doctor.sh — conformance check for the melodic.worktreeroot
# convention (#2612). The includeIf machinery the convention leans on for
# per-identity/per-repository roots fails UNIFORMLY QUIETLY: an unknown
# condition keyword, a missing include file, a plain value parsed after an
# includeIf, a scope flag skipping every include, and a 2.56-only condition on
# an older git all produce rc=0 and zero bytes of stderr, so a typo'd condition
# is indistinguishable from an unset key. This doctor makes those failure
# classes loud, and names WHICH rule supplied the repository's root.
#
# Convention owner doc: reference/worktree-root-convention.md. The resolution
# this doctor reports on is the one scripts/worktree-create.sh performs.
#
# Usage:
#   worktree-root-doctor.sh [--repo-dir <dir>]
#
# Output: one finding per line — `ok:` / `info:` / `warn:` / `error:`.
# Exit codes:
#   0  no warnings or errors
#   1  at least one warn/error finding
#   2  usage error
#
# Checked here (each mapped to a silent-failure class from #2612):
#   * dubious-ownership / non-repository fallback — `rev-parse --git-dir` gate;
#     without it a config read returns the GLOBAL default as though it were the
#     repository's answer (rc=0, no stderr).
#   * which rule supplied the root — `--show-origin` per value; `--show-scope`
#     is useless here (it collapses a conditionally-included file to `global`).
#   * a plain value parsed after an include-supplied one — precedence is parse
#     order, not specificity, so a `[melodic] worktreeroot` below the includeIf
#     block silently overrides every identity include.
#   * declared-but-unfired includeIf conditions — `git config --list` emits
#     `includeif.<condition>.path` for every DECLARED condition, matched or
#     not, so declared can be diffed against what actually contributed values.
#   * an include path pointing at a nonexistent file (rc=0, silent upstream).
#   * unrecognized condition keywords, and version-floor conditions
#     (`worktree:`/`worktree/i:` need git >= 2.56; older gits skip them with no
#     diagnostic).
#   * `gitdir:` without `/i` on a Windows shell — gitdir matching is
#     case-sensitive even on case-insensitive NTFS, and only the pattern
#     author's spelling matters.
#   * `hasconfig:` in use — libgit2 clients (gitui, TortoiseGit, bindings)
#     implement gitdir/gitdir-i/onbranch but NOT hasconfig, and unrecognized
#     conditions fail silently there; fine for melodic.* (CLI-only readers),
#     fatal for an identity split.
#   * identity partials — an include that sets user.email but not
#     user.signingkey while signing is configured globally leaks the global
#     key into that identity's commits (and an SSH-signed mismatch verifies
#     Good locally, so nothing downstream catches it).
#   * scoped-read divergence — reported as info: consumers must never pass a
#     scope flag without --includes, and this names what such a read would
#     return here.
#
# NOT machine-checked here, reported as a standing note instead: NTFS
# junction-anchored patterns (match nothing in either direction, contradicting
# the manpage's symlink claim — anchor patterns at canonical targets) and bare
# repositories (no `/.git` suffix, so `**/<name>/.git` patterns miss them; the
# suffix shape IS flagged when a declared pattern carries it).

set -uo pipefail

PROG=${0##*/}

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
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# expand_tilde <path> — a leading ~/ against $HOME, best-effort.
expand_tilde() {
  local p="$1"
  # SC2088: matching the literal unexpanded tilde is the point — config values
  # arrive verbatim, never shell-expanded.
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    printf '%s/%s' "${HOME%/}" "${p#\~/}"
  else
    printf '%s' "$p"
  fi
}

# canon <path> — physical path when a resolver exists, the input otherwise.
# Only used for comparisons, never displayed. Same realpath||readlink -f idiom
# as hooks/hook-utils.sh (auto-guarded by shell-portability-lint).
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

# --- Gate: the repository must actually resolve -------------------------------
# Under dubious ownership (safe.directory) or outside a repository entirely,
# `git -C <dir> config --get <key>` still exits 0 and returns the GLOBAL value
# as though it were the repository's answer. Every read below is meaningless
# until this gate passes, so a failure here is the whole report.
if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
  err "repository unreadable at $repo_dir — not a git repository, or dubious ownership (safe.directory). Until this resolves, any 'git -C <here> config --get melodic.worktreeroot' silently returns the GLOBAL value as if it were this repository's answer (rc=0, no stderr). Fix: run from a repository, or 'git config --global --add safe.directory <path>'."
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

# --- Declared includeIf conditions, and which files actually contributed ------
# `git config --list --show-origin` searches all files (includes ON — the
# default when no scope flag is given), emitting `includeif.<cond>.path` for
# every declared condition whether or not it matched. Under -z each entry is
# TWO NUL-delimited records — `origin<NUL>key<LF>value<NUL>` — so a value
# carrying a newline cannot shear a record; keys cannot contain NUL or the LF
# that ends them.
declare -a inc_conds=() inc_paths=() inc_origins=() inc_resolved=()
declare -A contributing_origin=()

while IFS= read -r -d '' origin && IFS= read -r -d '' kv; do
  key="${kv%%$'\n'*}"
  val="${kv#*$'\n'}"
  [[ "$kv" == *$'\n'* ]] || {
    key="$kv"
    val=""
  }
  # Origin is `file:<path>` for file-backed config; other origin types
  # (blob:, command line:) are not include machinery.
  ofile=""
  [[ "$origin" == file:* ]] && ofile="${origin#file:}"
  [[ -n "$ofile" ]] && contributing_origin["$(canon "$ofile")"]=1
  if [[ "$key" == includeif.*.path ]]; then
    cond="${key#includeif.}"
    cond="${cond%.path}"
    inc_conds+=("$cond")
    inc_paths+=("$val")
    inc_origins+=("$ofile")
    # A relative include path resolves against the DECLARING file's directory.
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
  local c
  c="$(canon "$1")"
  local k
  for k in ${inc_resolved[@]+"${inc_resolved[@]}"}; do
    [[ "$k" == "$c" ]] && return 0
  done
  return 1
}

for idx in ${inc_conds[@]+"${!inc_conds[@]}"}; do
  cond="${inc_conds[idx]}"
  resolved="${inc_resolved[idx]}"
  # Fired-ness is per target FILE, not per condition — git does not report which
  # condition spliced a file when several name the same one, so a file another
  # condition pulled in reads as contributing for all of them.
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
      warn "includeIf \"$cond\" uses case-sensitive gitdir: on a Windows shell — a lowercase drive letter, 8.3 short name, or casing differing from the canonical gitdir matches NOTHING (only the pattern author's spelling matters). Use gitdir/i: on Windows."
      ;;
    *) ;;
    esac
    ;;
  gitdir/i:*) ;;
  onbranch:*) ;;
  hasconfig:remote.*.url:*)
    note "includeIf \"$cond\": hasconfig: is unimplemented in libgit2 (gitui, TortoiseGit, git2/nodegit/pygit2 bindings), where unrecognized conditions fail SILENTLY, and JGit/go-git resolve no includeIf at all — fine for melodic.* (CLI-shelling readers only), unsafe as the identity layer (user.email etc.). Use gitdir/i: for identity."
    ;;
  worktree:* | worktree/i:*)
    if ((git_version_num < 256)); then
      warn "includeIf \"$cond\" needs git >= 2.56; this machine's git skips it SILENTLY (rc=0, no stderr) — the condition never fires here"
    fi
    ;;
  *)
    warn "includeIf \"$cond\" is not a keyword this git recognizes (gitdir:, gitdir/i:, onbranch:, hasconfig:remote.*.url:, worktree:, worktree/i:) — unknown keywords are skipped SILENTLY, so a typo here is indistinguishable from an unset key"
    ;;
  esac
  case "$cond" in
  gitdir:*/.git | gitdir/i:*/.git)
    note "includeIf \"$cond\" ends in /.git — a BARE repository's gitdir has no /.git suffix, so this pattern silently misses bare clones"
    ;;
  *) ;;
  esac
done

# --- Resolution: which rule supplied melodic.worktreeroot ----------------------
declare -a val_origins=() val_values=()
while IFS= read -r -d '' origin && IFS= read -r -d '' val; do
  # Same alternating -z framing as above, except --get-all emits the VALUE
  # alone as the second record (no key<LF> prefix — measured, not assumed).
  ofile=""
  [[ "$origin" == file:* ]] && ofile="${origin#file:}"
  val_origins+=("$ofile")
  val_values+=("$val")
done < <(git -C "$repo_dir" config --show-origin -z --get-all --type=path melodic.worktreeroot 2>/dev/null | tr -d '\r')

nvals=${#val_values[@]}
if ((nvals == 0)); then
  note "melodic.worktreeroot is unset — the creation helper falls through to the worktree_root plugin option, then the plugin data directory. Set the key so every consumer can read the root: git config --global melodic.worktreeroot <dir-outside-every-repo>"
else
  win_idx=$((nvals - 1))
  win_val="${val_values[win_idx]}"
  win_origin="${val_origins[win_idx]}"
  supplied_by="$win_origin"
  # shellcheck disable=SC2310  # pure predicate; both branches are handled
  if is_include_file "$win_origin"; then
    for idx in "${!inc_resolved[@]}"; do
      if [[ "${inc_resolved[idx]}" == "$(canon "$win_origin")" ]]; then
        supplied_by="includeIf \"${inc_conds[idx]}\" via $win_origin"
        break
      fi
    done
  fi
  ok "melodic.worktreeroot = $win_val (supplied by $supplied_by)"

  # Parse order is precedence: a plain value the parser meets AFTER an
  # include-supplied one silently overrides every identity include.
  if ((nvals > 1)); then
    losing_include=0
    for ((idx = 0; idx < win_idx; idx++)); do
      # shellcheck disable=SC2310  # pure predicate; both branches are handled
      if is_include_file "${val_origins[idx]}"; then
        losing_include=1
        break
      fi
    done
    # shellcheck disable=SC2310  # pure predicate; both branches are handled
    if ((losing_include)) && ! is_include_file "$win_origin"; then
      warn "a plain melodic.worktreeroot in $win_origin is parsed AFTER an include-supplied value and silently overrides it — precedence is parse order, not specificity. If the include is meant to win, move the plain default ABOVE the includeIf block."
    elif is_include_file "$win_origin"; then
      # The recommended layout: a plain machine default parsed first, the
      # include's more-specific answer after it. Say so — the absence of a
      # confirmation is indistinguishable from an unchecked class.
      note "several values are set ($nvals); last parsed wins, and the winner comes from an include — the layering is working"
    fi
  fi

  # Scoped-read divergence: a consumer passing a scope flag without --includes
  # gets a DIFFERENT answer than the correct all-files read.
  scoped_val="$(git config --global --get --type=path melodic.worktreeroot 2>/dev/null | tail -n 1 | tr -d '\r')"
  if [[ "$scoped_val" != "$win_val" ]]; then
    note "a scoped read ('git config --global --get melodic.worktreeroot', includes OFF by default when a scope flag is given) returns '${scoped_val:-<nothing>}' here, not '$win_val' — consumers must never pass a scope flag without --includes"
  fi

  # The root must satisfy the invariant the key exists for.
  root_expanded="$(expand_tilde "$win_val")"
  if [[ -e "$root_expanded" ]]; then
    if git -C "$root_expanded" rev-parse --show-toplevel >/dev/null 2>&1; then
      warn "the resolved root $win_val sits INSIDE a git working tree — the one placement the convention exists to prevent; point it at a directory outside every repository"
    fi
  fi
fi

# --- Identity partials ---------------------------------------------------------
# An include that flips user.email without the signing/transport keys leaks the
# global ones into that identity's commits — and a wrong SSH signing key still
# verifies Good locally (git derives the principal from the signature), so the
# leak surfaces only on the forge.
signing_configured=""
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

# --- Standing notes: classes no script can probe from here ---------------------
note "not machine-checked here: NTFS junction-anchored gitdir patterns match nothing in either direction (anchor at canonical targets), and --show-scope collapses include-supplied values to 'global' (use --show-origin, as this doctor does)"

((FINDINGS == 0)) || exit 1
exit 0

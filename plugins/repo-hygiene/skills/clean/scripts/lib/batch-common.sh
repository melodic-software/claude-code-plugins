# shellcheck shell=bash
# shellcheck disable=SC2034 # BATCH_ARG_ERROR is read by the sourcing scripts
# Shared plumbing for the fleet (batch) clean orchestrator. Sourceable; not run
# directly. Reuses clean_path_key / clean_skip_matches from clean-common.sh —
# the separator-agnostic normalization + skip matching proven out by tree-batch.
#
# tree-batch (git-tree-reset-batch.sh) reads lines, matches the skip ledger and
# emits per-repo records through this module, but its resolve-dedup loop is
# inline: batch_resolve_repos additionally runs each input through
# batch_normalize_input (backslash folding), which tree-batch's loop does not, so
# adopting it there is a behavior change rather than a lift. Measured on the
# distinguishing input — a real git repo whose directory name contains a literal
# backslash: tree-batch's loop resolves it and resets it, batch_resolve_repos
# folds the name to a path that does not exist and reports it blocked
# `not-a-directory`. Dropping a repo the caller named is the defect class this
# tier exists to close, so the loop stays inline.

# shellcheck source=clean-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/clean-common.sh"

# batch_normalize_input <path> — echo a git-friendly path: backslashes to forward
# slashes, strip a trailing CR, collapse trailing slashes. `ghq list -p` emits
# `<drive>:\repos\...` — backslashes break `xargs` (escapes eaten) and bash `[[ -d ]]`;
# git and `git check-ignore` want the `<drive>:/repos/...` drive-letter forward-slash
# form (git rev-parse --show-toplevel already emits it, so a normalized input
# compares equal to a resolved toplevel). Drive letter is preserved as-is.
batch_normalize_input() {
  local v="${1%$'\r'}"
  v="${v//\\//}"
  while [[ "$v" == */ && "$v" != "/" ]]; do v="${v%/}"; done
  printf '%s' "$v"
}

# batch_read_lines_into <array-name> <file|-> — append non-empty CR-stripped
# lines. Raw (unnormalized): repo paths are normalized at resolve time, skip
# entries are normalized by clean_skip_matches, so neither is pre-mangled here.
#
# Exit status is a source-open verdict, not a record-read verdict. Bash `read`
# returns nonzero at ordinary EOF (help read: "unless end-of-file is
# encountered"); that is not evidence the containing file operation failed.
#   0  the selected source was opened/accepted and consumed to ordinary EOF.
#      Empty input, blank lines, a trailing blank line, and a final
#      non-newline-terminated line are all success.
#   1  a named source is missing, not a regular file, or cannot be opened/read.
#      No input-content shape returns 1. For `-`, ordinary stdin EOF is success.
batch_read_lines_into() {
  local -n _dest="$1"
  local src="$2" line
  if [[ "$src" == "-" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -n "$line" ]] && _dest+=("$line")
    done
    return 0
  fi
  # Named source: reject missing/non-regular before open so a directory never
  # blocks on `read`. Then open explicitly so a permission/open failure is
  # retained (a `while ... done <"$src"` that never enters the body would
  # otherwise look like success).
  [[ -f "$src" ]] || return 1
  # Fixed fd 3: Bash `{fd}` only allocates from 10 upward, so `ulimit -n 10`
  # makes that open fail even when the list file is readable.
  exec 3<"$src" || return 1
  while IFS= read -r -u 3 line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "$line" ]] && _dest+=("$line")
  done
  exec 3<&-
  # Explicit success: do not let the last `[[ -n "$line" ]]` (false on a
  # trailing blank, or on the EOF guard after a delimiter) become the result.
  return 0
}

# Skip-list ledger. BATCH_SKIP_INPUTS is filled by each orchestrator's --skip /
# --skip-from parsing; BATCH_SKIP_HITS parallels it one slot per entry, so an
# entry that protected nothing can be surfaced instead of failing silently (the
# original fleet-reset data loss). BATCH_SKIP_MATCHED carries the last entry that
# matched the most recent batch_skip_match call.
BATCH_SKIP_INPUTS=()
BATCH_SKIP_HITS=()
BATCH_SKIP_MATCHED=""

# batch_reset_skip_hits — size the hit ledger to the skip list, every slot 0.
# Pre-filling is load-bearing, not cosmetic: under `set -u` a read of an array
# element that was never assigned is an unbound-variable error, and
# batch_report_unmatched_skips reads EVERY slot, including entries no repo ever
# matched. Call once, after the skip list is fully parsed.
batch_reset_skip_hits() {
  local s
  BATCH_SKIP_HITS=()
  for ((s = 0; s < ${#BATCH_SKIP_INPUTS[@]}; s++)); do BATCH_SKIP_HITS+=(0); done
}

# batch_skip_match <repo_key> — does any skip entry cover this repo? Sets
# BATCH_SKIP_MATCHED to the matching entry (the LAST one, when several match) for
# the caller's Reason line, and returns 0/1 so the caller can branch without
# re-testing. Every matching entry is marked hit, not just the reported one: an
# entry that did protect a repo must never be reported UnmatchedSkip.
batch_skip_match() {
  local repo_key="$1" s
  BATCH_SKIP_MATCHED=""
  for ((s = 0; s < ${#BATCH_SKIP_INPUTS[@]}; s++)); do
    if clean_skip_matches "$repo_key" "${BATCH_SKIP_INPUTS[$s]}"; then
      BATCH_SKIP_MATCHED="${BATCH_SKIP_INPUTS[$s]}"
      BATCH_SKIP_HITS[s]=1
    fi
  done
  [[ -n "$BATCH_SKIP_MATCHED" ]]
}

# batch_report_unmatched_skips — print one `UnmatchedSkip: <entry>` line per skip
# entry that matched no repo in this run.
batch_report_unmatched_skips() {
  local s
  for ((s = 0; s < ${#BATCH_SKIP_INPUTS[@]}; s++)); do
    if [[ "${BATCH_SKIP_HITS[$s]}" -eq 0 ]]; then
      printf 'UnmatchedSkip: %s\n' "${BATCH_SKIP_INPUTS[$s]}"
    fi
  done
}

# Resolve-and-dedup accumulators, populated by batch_resolve_repos. Reset per call.
BATCH_TOPS=()
BATCH_KEYS=()
BATCH_INVALID=()
BATCH_INVALID_REASONS=()

# batch_resolve_repos <input>... — normalize each input, resolve to its canonical
# git toplevel, dedup by clean_path_key. A non-directory or non-git input is
# recorded in BATCH_INVALID / BATCH_INVALID_REASONS (surfaced as a blocked
# outcome by the caller) rather than silently dropped. Populates BATCH_TOPS /
# BATCH_KEYS with the surviving unique repos in first-seen order.
batch_resolve_repos() {
  BATCH_TOPS=()
  BATCH_KEYS=()
  BATCH_INVALID=()
  BATCH_INVALID_REASONS=()
  local input norm top key
  local -A seen_keys=()
  for input in "$@"; do
    [[ -n "$input" ]] || continue
    norm="$(batch_normalize_input "$input")"
    [[ -n "$norm" ]] || continue
    if [[ ! -d "$norm" ]]; then
      BATCH_INVALID+=("$input")
      BATCH_INVALID_REASONS+=("not-a-directory")
      continue
    fi
    top="$(git -C "$norm" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
    if [[ -z "$top" ]]; then
      BATCH_INVALID+=("$input")
      BATCH_INVALID_REASONS+=("not-a-git-repo")
      continue
    fi
    key="$(clean_path_key "$top")"
    [[ -n "${seen_keys[$key]:-}" ]] && continue
    seen_keys["$key"]=1
    BATCH_TOPS+=("$top")
    BATCH_KEYS+=("$key")
  done
}

# batch_remote_key <repo> — echo the repo's origin URL reduced to `host/path`: no
# scheme, no user@, host lowercased, no trailing `/` or `.git`, scp form
# (`git@host:o/r`) folded into the URL form. Empty when there is no origin.
batch_remote_key() {
  local u scp=1
  u="$(git -C "$1" remote get-url origin 2>/dev/null | tr -d '\r')"
  [[ -n "$u" ]] || return 0
  [[ "$u" == *://* ]] && scp=0
  u="${u#*://}"
  u="${u#*@}"
  [[ $scp -eq 1 && "$u" =~ ^[^/:]+: ]] && u="${u/:/\/}"
  u="${u%/}"
  u="${u%.git}"
  printf '%s%s' "$(tr '[:upper:]' '[:lower:]' <<<"${u%%/*}")" "${u#"${u%%/*}"}"
}

# Duplicate-clone accumulators, populated by batch_dedupe_clones.
BATCH_DUPS=()
BATCH_DUP_OF=()

# batch_dedupe_clones — drop from BATCH_TOPS / BATCH_KEYS every repo whose origin
# (batch_remote_key) matches an earlier one, keeping the first; the dropped path
# and the kept path go to BATCH_DUPS / BATCH_DUP_OF. Linked worktrees of one
# repository share a git common dir and are not clones: they stay, and the
# per-tier common-dir dedup handles them. A repo with no origin never dedupes.
batch_dedupe_clones() {
  local i top rk kept_top common kept_common
  local -A first=()
  local -a tops=() keys=()
  BATCH_DUPS=()
  BATCH_DUP_OF=()
  for ((i = 0; i < ${#BATCH_TOPS[@]}; i++)); do
    top="${BATCH_TOPS[$i]}"
    rk="$(batch_remote_key "$top")"
    if [[ -n "$rk" && -n "${first[$rk]:-}" ]]; then
      kept_top="${first[$rk]}"
      common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
      kept_common="$(git -C "$kept_top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
      if [[ -z "$common" || "$common" != "$kept_common" ]]; then
        BATCH_DUPS+=("$top")
        BATCH_DUP_OF+=("$kept_top")
        continue
      fi
    fi
    [[ -n "$rk" && -z "${first[$rk]:-}" ]] && first["$rk"]="$top"
    tops+=("$top")
    keys+=("${BATCH_KEYS[$i]}")
  done
  BATCH_TOPS=("${tops[@]}")
  BATCH_KEYS=("${keys[@]}")
}

# batch_emit_dups — one skipped block per duplicate clone.
batch_emit_dups() {
  local i
  for ((i = 0; i < ${#BATCH_DUPS[@]}; i++)); do
    batch_emit "${BATCH_DUPS[$i]}" skipped "skipped duplicate of ${BATCH_DUP_OF[$i]}"
  done
  return 0
}

# batch_discover_fleet <array-name> — append the repos this machine knows about:
# every `ghq list -p` entry (when ghq resolves) and the chezmoi source repo (when
# chezmoi resolves and its source path is inside a git work tree).
batch_discover_fleet() {
  local -n _fleet="$1"
  local src
  if command -v ghq >/dev/null 2>&1; then
    batch_read_lines_into _fleet - < <(ghq list -p 2>/dev/null)
  fi
  if command -v chezmoi >/dev/null 2>&1; then
    src="$(chezmoi source-path 2>/dev/null | tr -d '\r')"
    if [[ -n "$src" && -d "$src" ]] && git -C "$src" rev-parse --show-toplevel >/dev/null 2>&1; then
      _fleet+=("$src")
    fi
  fi
}

# Unique shared-object-store accumulators, populated by batch_add_gitdir.
BATCH_GITDIR_KEYS=()
BATCH_GITDIR_TOPS=()

# batch_reset_gitdirs — clear the git-common-dir dedup set (call once per run).
batch_reset_gitdirs() {
  BATCH_GITDIR_KEYS=()
  BATCH_GITDIR_TOPS=()
}

# batch_add_gitdir <repo_top> — resolve a repo's shared object store
# (`--git-common-dir`) and record it once. Linked worktrees share the main
# clone's objects, so git gc / prune must run once per unique common dir, not per
# worktree. The FIRST worktree top that maps to a common dir is kept as the
# representative to `cd` into (never the bare `.git` dir — prune/gc need a work
# tree cwd). Return: 0 newly added, 2 duplicate (already recorded), 1 unresolved.
batch_add_gitdir() {
  local top="$1" common key e
  common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
  if [[ -z "$common" ]]; then
    common="$(git -C "$top" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
    [[ -n "$common" && "$common" != /* && "$common" != ?:/* ]] && common="$top/$common"
  fi
  [[ -n "$common" ]] || return 1
  key="$(clean_path_key "$common")"
  for e in "${BATCH_GITDIR_KEYS[@]}"; do
    [[ "$e" == "$key" ]] && return 2
  done
  BATCH_GITDIR_KEYS+=("$key")
  BATCH_GITDIR_TOPS+=("$top")
  return 0
}

# batch_emit <repo> <outcome> <reason> — one per-repo record block.
batch_emit() {
  printf 'Repo: %s\n' "$1"
  printf 'Outcome: %s\n' "$2"
  printf 'Reason: %s\n' "$3"
  printf '%s\n' '---'
}

# Repo-selection surface for the read-only audit scripts (git-branch-audit.sh,
# git-stash-audit.sh): the --repo / --repos-from / --skip / --skip-from that
# clean-batch.sh takes, without its gate, because an audit mutates nothing.
BATCH_REPO_INPUTS=()
BATCH_ARG_SHIFT=0
BATCH_ARG_ERROR=""

# batch_take_selection_arg <flag> [value...] — consume one selection flag and its
# values from the caller's remaining args. Pass "$@" whole; on return 0 the caller
# runs `shift "$BATCH_ARG_SHIFT"`. Returns 1 with BATCH_ARG_ERROR set on a missing
# value or an unreadable list file. --repo takes every consecutive non-flag word,
# so a shell glob arrives whole.
batch_take_selection_arg() {
  local flag="$1"
  BATCH_ARG_SHIFT=1
  shift
  case "$flag" in
  --repo)
    if [[ $# -lt 1 || "$1" == -* ]]; then
      BATCH_ARG_ERROR="--repo requires a directory"
      return 1
    fi
    while [[ $# -gt 0 && "$1" != -* ]]; do
      BATCH_REPO_INPUTS+=("$1")
      BATCH_ARG_SHIFT=$((BATCH_ARG_SHIFT + 1))
      shift
    done
    ;;
  --repos-from | --skip | --skip-from)
    if [[ $# -lt 1 ]]; then
      BATCH_ARG_ERROR="$flag requires a value"
      return 1
    fi
    BATCH_ARG_SHIFT=2
    if [[ "$flag" == --skip ]]; then
      BATCH_SKIP_INPUTS+=("$1")
    elif [[ "$flag" == --skip-from ]]; then
      batch_read_lines_into BATCH_SKIP_INPUTS "$1" || {
        BATCH_ARG_ERROR="file not found: $1"
        return 1
      }
    else
      batch_read_lines_into BATCH_REPO_INPUTS "$1" || {
        BATCH_ARG_ERROR="file not found: $1"
        return 1
      }
    fi
    ;;
  *)
    BATCH_ARG_ERROR="not a selection flag: $flag"
    return 1
    ;;
  esac
}

# batch_run_fleet <script> [child-arg...] — audit every repo batch_resolve_repos
# left in BATCH_TOPS, one at a time, by running <script> (an absolute path, given
# no selection flags) from inside the repo. An audited block is `Repo: <top>`, the
# child's output, `---`. A skip-listed repo, a repo whose git common dir was
# already audited (a linked worktree of an earlier repo), an unresolvable input,
# and a child that exits nonzero each get a batch_emit block instead, and none of
# them stops the fleet. Ends with `FleetSummary:` and returns 0.
batch_run_fleet() {
  local script="$1" i top out rc audited=0 skipped=0 dup=0 failed=0 blocked=0
  shift
  batch_reset_skip_hits
  batch_reset_gitdirs
  for ((i = 0; i < ${#BATCH_TOPS[@]}; i++)); do
    top="${BATCH_TOPS[$i]}"
    printf 'Progress: %s/%s %s\n' "$((i + 1))" "${#BATCH_TOPS[@]}" "$top" >&2
    if batch_skip_match "${BATCH_KEYS[$i]}"; then
      batch_emit "$top" skipped "skip-list ($BATCH_SKIP_MATCHED)"
      skipped=$((skipped + 1))
      continue
    fi
    batch_add_gitdir "$top"
    if [[ $? -eq 2 ]]; then
      batch_emit "$top" skipped "shares a git common dir with an audited repo"
      dup=$((dup + 1))
      continue
    fi
    out="$(cd "$top" && bash "$script" "$@")"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      batch_emit "$top" failed "audit exited $rc"
      printf '%s\n' "$out" >&2
      failed=$((failed + 1))
      continue
    fi
    printf 'Repo: %s\n%s\n%s\n' "$top" "$out" '---'
    audited=$((audited + 1))
  done
  for ((i = 0; i < ${#BATCH_INVALID[@]}; i++)); do
    batch_emit "${BATCH_INVALID[$i]}" blocked "${BATCH_INVALID_REASONS[$i]}"
    blocked=$((blocked + 1))
  done
  batch_report_unmatched_skips
  printf 'FleetSummary: repos=%s audited=%s skipped=%s duplicate=%s blocked=%s failed=%s\n' \
    "$((${#BATCH_TOPS[@]} + blocked))" "$audited" "$skipped" "$dup" "$blocked" "$failed"
  return 0
}

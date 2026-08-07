#!/usr/bin/env bash
# landed-work.sh — read-only landed-vs-stranded classification for git worktrees.
#
# Answers one question per worktree: if this checkout were removed and its branch
# deleted, would any commit be lost? A commit is STRANDED when it is unpushed AND
# its content is not already on the base. Everything else is recoverable, and the
# distinction is the only thing standing between a cleanup sweep and data loss.
#
# Read-only by construction: no fetch, no ref write, no checkout, no removal, no
# network. Every verdict is computed from refs already on disk, so a stale remote
# ref yields a conservative answer (see the fail-closed rule below), never a wrong
# destructive one.
#
# Consumers: the `worktree` skill's status and cleanup contexts. The script
# computes; prose maps the record to an operator disposition; the operator judges.
#
# FAIL-CLOSED RULE, which governs every branch below: only affirmative proof
# yields `landed=yes`. Every failed command, empty result set, unresolvable base,
# and ambiguity yields `?`, and a guard must treat `?` exactly as it treats `no`.
# The nuisance direction costs a confirmation prompt; the other direction destroys
# work.
#
# Method (measured, not assumed — see the three notes at each site):
#   * unpushed set is `HEAD --not --remotes`, never `--branches` and never
#     `@{upstream}..HEAD`;
#   * `landed` is decided by RANGE patch-id first, because a per-commit primitive
#     (including `git cherry`) cannot see a multi-commit squash-merge;
#   * patch ids are computed `--verbatim`, because the whitespace-stripping
#     default hashes `a b` and `ab` alike and would call two different contents
#     the same change;
#   * no affirmative verdict is drawn from an incomplete patch-id set — a commit
#     that produces no patch is invisible to patch-id, so the set has to account
#     for every non-merge commit before it can speak for the branch;
#   * the path-scoped two-dot fallback answers only whether the touched paths
#     differ from the base at all, and its verdict is stamped with the base SHA it
#     was computed against.
#
# Output: one TSV row per target, header first, on stdout. Diagnostics on stderr.
# Every field is non-empty — an absent value is `-` — so a consumer reading the
# row with `while IFS=$'\t' read` gets the columns it asked for. Tab is IFS
# whitespace and bash collapses runs of it, so an empty field would shift every
# later column left and hand the reader the wrong value under the right name.
#
# Exit codes:
#   0  success — every target classified
#   2  usage error
#   3  no target resolved (no worktree found for the given scope)
#   4  environment error — git absent, or the scope is not a git repository
#   5  row-count assertion failed — the emitted rows do not match the worktree
#      list the run was supposed to cover. A truncated pass must fail loudly; a
#      short list read as "nothing at risk" is the failure mode this guards.

set -uo pipefail

PROG=${0##*/}

usage() {
  cat >&2 <<EOF
$PROG — read-only landed-vs-stranded classification for git worktrees.

Usage:
  $PROG [--repo-dir <dir>] [--worktree <path>]... [--base <ref>]
        [--merged-refs-file <path>] [--no-peers]
  $PROG --path-key <value>
  $PROG --help

Options:
  --repo-dir <dir>    Repository whose worktrees are classified. Default: the
                      current directory. Ignored when --worktree is given.
  --worktree <path>   Classify exactly this path instead of enumerating.
                      Repeatable. A path that is not a work-tree ROOT is
                      reported as notgit rather than silently inheriting the
                      containing repository's state.
  --base <ref>        Base to test landedness against. Default: origin/HEAD,
                      then origin/main, then origin/master. No base resolves
                      to landed=? — never to no.
  --merged-refs-file <path>
                      Newline-separated branch names whose pull request is
                      MERGED. A landed=no worktree whose branch appears here is
                      a superseded draft, not stranded work: the base holds a
                      later revision of the same change. Collected by the
                      caller (gh), so this script stays offline.
  --no-peers          Skip peer detection (another worktree holding the same
                      commits). Peer detection is O(n^2) ancestry probes.
  --path-key <value>  Print the path comparison key for <value> and exit. A
                      debug seam the test suite asserts the normalizer through.

Columns:
  path branch head unpushed landed method base inprogress staged unstaged
  conflicted untracked peers risk reason
EOF
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "${2:-2}"
}

# ---------------------------------------------------------------------------
# Path comparison
# ---------------------------------------------------------------------------

# Windows shells render a drive as /d/repos/x while git emits D:/repos/x, so the
# two operands compared here differ by CONSTRUCTION — one comes from git, the
# other from the filesystem. audit-fleet.sh:500's path_key() never had to
# reconcile that because both of its operands come from one source.
#
# cygpath is not used: worktree-create.sh:247 rejects it because it resolves
# relative paths against the CWD and rewrites MSYS /tmp paths, and its own remedy
# is a pure separator swap that defers all resolution to existing machinery. A
# pure drive-letter swap is that same remedy, so this follows the precedent
# rather than overturning it.
CASE_INSENSITIVE_PATHS=false
WINDOWS_PATHS=false
case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  CASE_INSENSITIVE_PATHS=true
  WINDOWS_PATHS=true
  ;;
*) ;;
esac

path_key() {
  local value="${1//\\//}"
  if [[ "$WINDOWS_PATHS" == "true" ]]; then
    case "$value" in
    /?/*) value="${value:1:1}:${value:2}" ;;
    /?) value="${value:1:1}:" ;;
    *) ;;
    esac
  fi
  while [[ "$value" == */ ]]; do value="${value%/}"; done
  if [[ "$CASE_INSENSITIVE_PATHS" == "true" ]]; then
    printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
  else
    printf '%s' "$value"
  fi
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

REPO_DIR="."
BASE_REF=""
MERGED_REFS_FILE=""
DO_PEERS=true
EXPLICIT_TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --path-key)
    [[ $# -ge 2 ]] || die "--path-key requires a value"
    path_key "$2"
    printf '\n'
    exit 0
    ;;
  --repo-dir)
    [[ $# -ge 2 ]] || die "--repo-dir requires a value"
    REPO_DIR="$2"
    shift 2
    ;;
  --worktree)
    [[ $# -ge 2 ]] || die "--worktree requires a value"
    EXPLICIT_TARGETS+=("$2")
    shift 2
    ;;
  --base)
    [[ $# -ge 2 ]] || die "--base requires a value"
    BASE_REF="$2"
    shift 2
    ;;
  --merged-refs-file)
    [[ $# -ge 2 ]] || die "--merged-refs-file requires a value"
    MERGED_REFS_FILE="$2"
    shift 2
    ;;
  --no-peers)
    DO_PEERS=false
    shift
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git not found on PATH" 4

if [[ -n "$MERGED_REFS_FILE" && ! -f "$MERGED_REFS_FILE" ]]; then
  die "--merged-refs-file not found: $MERGED_REFS_FILE"
fi

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

# is_worktree_root <path>: true when <path> is the ROOT of a work tree.
#
# `rev-parse --is-inside-work-tree` cannot answer this — it returns true for an
# empty leftover directory inside a repository, because that directory genuinely
# IS inside the parent's work tree, and the parent's clean state is then reported
# as the husk's own. `--show-prefix` is the discriminator that needs no path
# arithmetic at all: it is empty exactly at a work-tree root and non-empty at any
# path below one, in every path spelling on every platform.
is_worktree_root() {
  local prefix
  prefix=$(git -C "$1" rev-parse --show-prefix 2>/dev/null) || return 1
  [[ -z "$prefix" ]]
}

# inprogress_of <path>: the in-progress sequencer operation, or `none`.
#
# Probed through `rev-parse --git-path`, never `<path>/.git/<file>`: a linked
# worktree's git dir is <main>/.git/worktrees/<name>, and only --git-path
# resolves the per-worktree vs common-dir split correctly — which is precisely
# the subject matter here.
inprogress_of() {
  local p="$1" name resolved
  for name in rebase-merge rebase-apply; do
    resolved=$(git -C "$p" rev-parse --git-path "$name" 2>/dev/null) || continue
    if [[ -d "$resolved" ]]; then
      printf 'rebase'
      return 0
    fi
  done
  for name in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    resolved=$(git -C "$p" rev-parse --git-path "$name" 2>/dev/null) || continue
    if [[ -e "$resolved" ]]; then
      case "$name" in
      MERGE_HEAD) printf 'merge' ;;
      CHERRY_PICK_HEAD) printf 'cherry-pick' ;;
      *) printf 'revert' ;;
      esac
      return 0
    fi
  done
  printf 'none'
}

S_STAGED=0
S_UNSTAGED=0
S_CONFLICTED=0
S_UNTRACKED=0

# status_counts <path>: split the working tree into four independent counts.
#
# A single `dirty` number is not a work-at-risk signal: a paused merge inflates
# it with the merge's own staged result, which is recomputable at any time,
# while the branch's own commits — the irreplaceable part — are carried by the
# unpushed/landed columns instead.
#
# Returns 1 when the status could not be read at all. A failed `git status` used
# to leave all four counts at their zero initialisation, which is exactly the
# shape of a clean worktree — so an unreadable index reported as clean, and a
# worktree with nothing unpushed then classified `ok`. Unknown must not wear
# clean's clothes.
status_counts() {
  local p="$1" line x y status_out="$WORKDIR/status.$$"
  S_STAGED=0
  S_UNSTAGED=0
  S_CONFLICTED=0
  S_UNTRACKED=0
  if ! git -C "$p" status --porcelain >"$status_out" 2>/dev/null; then
    rm -f "$status_out"
    return 1
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    x="${line:0:1}"
    y="${line:1:1}"
    case "$x$y" in
    '??')
      S_UNTRACKED=$((S_UNTRACKED + 1))
      continue
      ;;
    '!!') continue ;;
    DD | AU | UD | UA | DU | AA | UU)
      S_CONFLICTED=$((S_CONFLICTED + 1))
      continue
      ;;
    *) ;;
    esac
    [[ "$x" != " " ]] && S_STAGED=$((S_STAGED + 1))
    [[ "$y" != " " ]] && S_UNSTAGED=$((S_UNSTAGED + 1))
  done <"$status_out"
  rm -f "$status_out"
  return 0
}

# resolve_base <path>: the ref landedness is tested against, on stdout.
resolve_base() {
  local p="$1" ref
  if [[ -n "$BASE_REF" ]]; then
    printf '%s' "$BASE_REF"
    return 0
  fi
  if ref=$(git -C "$p" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s' "${ref#refs/remotes/}"
    return 0
  fi
  for ref in origin/main origin/master; do
    if git -C "$p" rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1; then
      printf '%s' "$ref"
      return 0
    fi
  done
  return 1
}

# patch_ids <path> <range> <outfile>: sorted patch-ids for every non-merge commit
# in <range>, one per line.
#
# One `git log -p` stream into one `git patch-id` process computes the whole set;
# the per-commit `git show | git patch-id` loop it replaces cost ~13s per
# worktree and bought nothing.
#
# `--no-merges` is explicit rather than incidental: `git log -p` emits no diff for
# a merge commit, so a merge-only range would otherwise produce an empty id set
# that is indistinguishable from a failed pipeline — and an empty set makes the
# "every branch id is on the base" test vacuously TRUE, which is a false `yes` in
# the data-loss direction. The caller compares this count against
# `rev-list --count --no-merges` over the same range for exactly that reason.
#
# `--verbatim`, not `--stable`. The default (and `--stable`) computes the id
# AFTER stripping whitespace, so `a b` and `ab` hash identically — two
# genuinely different contents, one id, and a branch whose unique change differs
# from the base's only in whitespace would classify as landed. Measured on git
# 2.54: both spellings produce `7ad14294…` under `--stable` and different ids
# under `--verbatim`. The two flags are mutually exclusive.
#
# What `--verbatim` costs is the whitespace tolerance that used to let an
# EOL-renormalized branch match: that case now falls through to the two-dot
# fallback and, failing there too, reports `no`. That is the fail-closed
# direction — a prompt rather than a loss — and it is the correct trade for a
# guard. What it does NOT cost is the squash case: the branch's range id still
# equals the squash commit's, and still matches after the base advances. Both
# verified in a fixture rather than assumed.
patch_ids() {
  local p="$1" range="$2" out="$3" patches="$WORKDIR/patches.$$"
  : >"$out"
  git -C "$p" log -p --no-merges --no-color "$range" >"$patches" 2>/dev/null || {
    rm -f "$patches"
    return 1
  }
  if [[ ! -s "$patches" ]]; then
    rm -f "$patches"
    return 0
  fi
  git patch-id --verbatim <"$patches" | cut -d' ' -f1 | sort >"$out" || {
    rm -f "$patches"
    return 1
  }
  rm -f "$patches"
  return 0
}

L_STATE="?"
L_METHOD="none"
L_BASE=""
L_REASON=""

# classify_landed <path>: set L_STATE (yes|no|?), L_METHOD, L_BASE, L_REASON.
classify_landed() {
  local p="$1" base base_sha mb range_id branch_expected branch_count
  local base_ids branch_ids touched
  L_STATE="?"
  L_METHOD="none"
  L_BASE=""
  L_REASON=""

  if ! base=$(resolve_base "$p"); then
    L_REASON="no-base-ref"
    return 0
  fi
  # An AMBIGUOUS base name is not a resolvable base. `refs/tags/release` and
  # `refs/heads/release` can both exist; rev-parse picks one by precedence and
  # says so only on stderr, so a silent pick could test against the wrong history
  # entirely. The warning is the signal, and it is treated as unresolvable.
  local base_err
  base_err="$WORKDIR/base-resolve.err"
  if ! base_sha=$(git -C "$p" rev-parse --verify "$base^{commit}" 2>"$base_err"); then
    L_REASON="base-unresolvable:$base"
    return 0
  fi
  if [[ -s "$base_err" ]] && grep -qi 'ambiguous' "$base_err"; then
    L_REASON="base-ref-ambiguous:$base"
    return 0
  fi
  L_BASE="$base@${base_sha:0:12}"
  # `--all`, and exactly one. A criss-cross history has several merge bases; a
  # plain `merge-base` silently returns one of them, and testing against a
  # different base than the one the work actually diverged at can produce a
  # favourable verdict for content that is not there.
  local mb_count
  mb=$(git -C "$p" merge-base --all "$base_sha" HEAD 2>/dev/null) || mb=""
  if [[ -z "$mb" ]]; then
    L_REASON="no-merge-base"
    return 0
  fi
  mb_count=$(printf '%s\n' "$mb" | grep -c .)
  if [[ "$mb_count" -ne 1 ]]; then
    L_REASON="ambiguous-merge-base-$mb_count-candidates"
    return 0
  fi

  # Base side. Memoized per (merge-base, base-tip): every sibling worktree of the
  # same repository sharing that pair reuses the set, and it is the step that
  # dominates the run.
  base_ids="$WORKDIR/base.$mb.$base_sha"
  if [[ ! -f "$base_ids" ]]; then
    local base_expected
    base_expected=$(git -C "$p" rev-list --count --no-merges "$mb..$base_sha" 2>/dev/null) || base_expected=""
    if [[ -z "$base_expected" ]]; then
      L_REASON="base-range-unreadable"
      return 0
    fi
    if ! patch_ids "$p" "$mb..$base_sha" "$base_ids"; then
      rm -f "$base_ids"
      L_REASON="base-patchid-failed"
      return 0
    fi
    # Count parity, the same check the branch side makes. An under-complete base
    # set can only make a match LESS likely, so this cannot be the difference
    # between `yes` and `no` today — it is here so the two sides cannot silently
    # diverge if either is ever refactored, and so a base range that failed to
    # render is named rather than quietly narrowing the id set it is compared
    # against.
    local base_count
    base_count=$(wc -l <"$base_ids" | tr -d '[:space:]')
    if [[ "$base_count" -ne "$base_expected" ]]; then
      rm -f "$base_ids"
      L_REASON="base-patchid-incomplete-$base_count-of-$base_expected-commits"
      return 0
    fi
  fi

  # Branch side. The COMPLETENESS check runs before any verdict, because both
  # affirmative arms below reason over the branch's commits and neither is sound
  # over an incomplete set: a commit that produces no patch (an empty commit, or
  # one whose diff git declined to render) is invisible to patch-id, so the id
  # set silently under-represents the branch. Requiring the id count to equal the
  # non-merge commit count is what makes "every id is on the base" a statement
  # about every commit rather than about the ones that happened to hash.
  branch_ids="$WORKDIR/branch.ids"
  branch_expected=$(git -C "$p" rev-list --count --no-merges "$mb..HEAD" 2>/dev/null) || branch_expected=""
  if [[ -z "$branch_expected" ]]; then
    L_REASON="branch-range-unreadable"
    return 0
  fi
  if ! patch_ids "$p" "$mb..HEAD" "$branch_ids"; then
    L_REASON="branch-patchid-failed"
    return 0
  fi
  branch_count=$(wc -l <"$branch_ids" | tr -d '[:space:]')
  if [[ "$branch_count" -ne "$branch_expected" ]]; then
    L_REASON="patchid-set-incomplete-$branch_count-of-$branch_expected-commits"
    return 0
  fi

  # Range first: a squash-merge collapses N commits into ONE patch, so no
  # individual commit's patch-id can match it, while the branch's RANGE id equals
  # the squash commit's exactly — and stays in the base's per-commit id set after
  # the base advances. Range-vs-range does NOT work: the base's own range id moves
  # as the base advances while the branch's does not.
  if git -C "$p" diff "$mb..HEAD" >"$WORKDIR/rangediff" 2>/dev/null && [[ -s "$WORKDIR/rangediff" ]]; then
    range_id=$(git patch-id --verbatim <"$WORKDIR/rangediff" | cut -d' ' -f1)
    if [[ -n "$range_id" ]] && grep -Fxq "$range_id" "$base_ids"; then
      L_STATE="yes"
      L_METHOD="range-patchid"
      return 0
    fi
  fi

  if [[ "$branch_expected" -gt 0 ]]; then
    # `comm`'s own exit status is checked, not just its output: a failed `comm`
    # produces empty stdout, and empty stdout is exactly the shape that means
    # "every branch id is on the base". Reading a failure as proof is the one
    # direction this script must never take.
    local unmatched="$WORKDIR/branch-not-on-base"
    if comm -23 "$branch_ids" "$base_ids" >"$unmatched" 2>/dev/null; then
      if [[ ! -s "$unmatched" ]]; then
        L_STATE="yes"
        L_METHOD="per-commit-patchid"
        return 0
      fi
    else
      L_REASON="patchid-set-comparison-failed"
      return 0
    fi
  fi

  # Path-scoped two-dot fallback. It answers ONE question soundly — whether the
  # branch's touched paths differ from the base at all — and that is the only
  # question it is now asked.
  #
  # The direction test that used to live here is gone, and its removal is the
  # point rather than a simplification: `git diff base..HEAD` reports deletions
  # for a branch that is merely BEHIND the base, and reports deletions for a
  # branch whose own unique work IS a deletion. Those two are byte-identical in
  # numstat, so "additions are zero" proved nothing and classified a
  # delete-only branch as landed — a false `yes` in the direction that destroys
  # work. The behind-not-stranded case it was written for is already caught by
  # the range patch-id above, which is why nothing needs to replace it.
  #
  # A verdict from here is only valid against the base tip stamped in L_BASE.
  touched="$WORKDIR/touched"
  if ! git -C "$p" diff --name-only --no-renames -z "$mb..HEAD" >"$touched" 2>/dev/null; then
    L_REASON="touched-paths-unreadable"
    return 0
  fi
  if [[ ! -s "$touched" ]]; then
    L_REASON="branch-adds-no-content"
    return 0
  fi

  # The touched paths are handed BACK to git as literal pathspecs rather than
  # matched against a second diff's text output. Two diff invocations only agree
  # on how a path is spelled when they agree on every escaping rule, and they did
  # not: `--name-only` quoted non-ASCII bytes while `--numstat` was pinned to
  # `core.quotepath=false`, so an i18n'd filename joined against nothing and the
  # empty join read as "identical to the base" — an unproven `yes`. Pinning
  # quotepath on both sides fixed that byte class and left another, since git
  # escapes `"`, `\`, and control characters regardless of that setting and only
  # `-z` suppresses it. Rather than chase escaping rules, git does its own path
  # matching here and the whole mismatch class goes away.
  #
  # `:(literal)` because a path is not a pattern: a file actually named
  # `star[1].txt`, or any path beginning with `:`, would otherwise be read as
  # pathspec magic and match something else entirely.
  local -a specs=()
  local pth
  while IFS= read -r -d '' pth; do specs+=(":(literal)$pth"); done <"$touched"
  if [[ ${#specs[@]} -eq 0 ]]; then
    L_REASON="touched-paths-unparseable"
    return 0
  fi

  # Chunked: a branch touching thousands of paths would otherwise exceed the
  # platform's command-line limit, and the failure would arrive as a non-zero
  # exit that looks like any other probe failure.
  local i rc differs=0
  local -a chunk=()
  for ((i = 0; i < ${#specs[@]}; i += 200)); do
    chunk=("${specs[@]:i:200}")
    git -C "$p" diff --quiet --no-renames "$base_sha..HEAD" -- "${chunk[@]}" 2>/dev/null
    rc=$?
    if [[ "$rc" -eq 1 ]]; then
      differs=1
      break
    fi
    if [[ "$rc" -ne 0 ]]; then
      L_REASON="two-dot-unreadable"
      return 0
    fi
  done
  if [[ "$differs" -eq 0 ]]; then
    L_STATE="yes"
    L_METHOD="two-dot-empty"
    return 0
  fi
  L_STATE="no"
  L_METHOD="two-dot"
  L_REASON="head-differs-from-base-on-${#specs[@]}-touched-path(s)"
}

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

WORKDIR=""
cleanup() { [[ -n "$WORKDIR" ]] && rm -rf "$WORKDIR"; }

T_PATH=()
T_BRANCH=()
T_HEAD=()

collect_targets() {
  local line path head branch detached
  if [[ ${#EXPLICIT_TARGETS[@]} -gt 0 ]]; then
    for path in "${EXPLICIT_TARGETS[@]}"; do
      T_PATH+=("$path")
      T_BRANCH+=("")
      T_HEAD+=("")
    done
    return 0
  fi
  git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 ||
    die "not a git repository: $REPO_DIR" 4

  # Captured to a file and status-checked BEFORE parsing, not streamed through a
  # process substitution. A process substitution's exit status is invisible to
  # the loop, so an enumeration that failed halfway produced a short list that
  # every downstream count — the row-count assertion included — then agreed with.
  # The assertion can only catch a truncated PASS; a truncated ENUMERATION has to
  # be caught here or not at all.
  #
  # `-z` because a worktree path may contain a newline, which line-oriented
  # parsing of `--porcelain` splits into a path that does not exist. Git
  # documents `-z` as the newline-safe form for exactly this.
  local porcelain="$WORKDIR/worktree-list"
  if ! git -C "$REPO_DIR" worktree list --porcelain -z >"$porcelain" 2>/dev/null; then
    die "git worktree list failed in $REPO_DIR — refusing to report a partial inventory" 4
  fi
  path=""
  head=""
  branch=""
  detached=0
  while IFS= read -r -d '' line; do
    case "$line" in
    "worktree "*)
      # A new record begins. Flush the previous one here rather than on a blank
      # separator: under -z the records are NUL-delimited fields, and the final
      # record has no trailing separator of its own.
      if [[ -n "$path" ]]; then
        T_PATH+=("$path")
        [[ "$detached" -eq 1 ]] && branch="(detached)"
        T_BRANCH+=("$branch")
        T_HEAD+=("$head")
      fi
      path="${line#worktree }"
      head=""
      branch=""
      detached=0
      ;;
    "HEAD "*) head="${line#HEAD }" ;;
    "branch "*) branch="${line#branch refs/heads/}" ;;
    "detached") detached=1 ;;
    *) ;;
    esac
  done <"$porcelain"
  if [[ -n "$path" ]]; then
    T_PATH+=("$path")
    [[ "$detached" -eq 1 ]] && branch="(detached)"
    T_BRANCH+=("$branch")
    T_HEAD+=("$head")
  fi
}

# assert_row_count <expected> <actual>: a pass that covered fewer worktrees than
# it enumerated must fail loudly. A short list silently reads as "nothing at
# risk", which is the one failure mode a stranded-work detector cannot have.
assert_row_count() {
  local expected="$1" actual="$2"
  if [[ "$expected" -ne "$actual" ]]; then
    printf '%s: row-count assertion failed — enumerated %s worktree(s), emitted %s row(s)\n' \
      "$PROG" "$expected" "$actual" >&2
    return 5
  fi
  return 0
}

# Sourcing seam: `LANDED_WORK_LIB=1 . landed-work.sh` defines the functions above
# without running the collector, so assert_row_count — whose failure path cannot
# be provoked through the CLI — is directly testable.
[[ -n "${LANDED_WORK_LIB:-}" ]] && return 0

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/landed-work.XXXXXX") || die "cannot create work directory" 4
trap cleanup EXIT

collect_targets
[[ ${#T_PATH[@]} -gt 0 ]] || die "no worktree found for the given scope" 3

R_UNPUSHED=()
R_LANDED=()
R_METHOD=()
R_BASE=()
R_INPROGRESS=()
R_STAGED=()
R_UNSTAGED=()
R_CONFLICTED=()
R_UNTRACKED=()
R_REASON=()
R_NOTGIT=()
R_BARE=()

merged_ref() {
  local name="$1"
  [[ -n "$MERGED_REFS_FILE" && -n "$name" && "$name" != "(detached)" ]] || return 1
  grep -Fxq "$name" "$MERGED_REFS_FILE"
}

idx=0
while [[ $idx -lt ${#T_PATH[@]} ]]; do
  p="${T_PATH[$idx]}"
  reason=""
  if [[ ! -d "$p" ]] || ! is_worktree_root "$p"; then
    R_NOTGIT+=("yes")
    R_BARE+=("no")
    R_UNPUSHED+=("?")
    R_LANDED+=("?")
    R_METHOD+=("none")
    R_BASE+=("")
    R_INPROGRESS+=("?")
    R_STAGED+=("?")
    R_UNSTAGED+=("?")
    R_CONFLICTED+=("?")
    R_UNTRACKED+=("?")
    if [[ ! -d "$p" ]]; then
      R_REASON+=("path-absent")
    else
      R_REASON+=("not-a-worktree-root; probing it with git -C reports the containing repository")
    fi
    idx=$((idx + 1))
    continue
  fi
  R_NOTGIT+=("no")

  # A bare-clone hub's own entry is the first row `git worktree list` emits, and
  # it carries no HEAD. It passes the work-tree-root probe (a bare repository's
  # --show-prefix is empty), so without this it would reach the landed
  # computation, fail at merge-base, and report a healthy hub as UNKNOWN.
  if [[ "$(git -C "$p" rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
    R_UNPUSHED+=("n/a")
    R_LANDED+=("n/a")
    R_METHOD+=("none")
    R_BASE+=("")
    R_INPROGRESS+=("none")
    R_STAGED+=("0")
    R_UNSTAGED+=("0")
    R_CONFLICTED+=("0")
    R_UNTRACKED+=("0")
    R_BARE+=("yes")
    R_REASON+=("bare-repository; holds no working tree to strand")
    T_BRANCH[idx]="(bare)"
    idx=$((idx + 1))
    continue
  fi
  R_BARE+=("no")

  # HEAD, never --branches: on a detached HEAD --branches reports every OTHER
  # branch in the repository and says nothing about the commits this worktree
  # actually holds — which is the only case where removal makes commits
  # unreachable immediately. `@{upstream}..HEAD` is equally wrong here: a
  # worktree branch created locally has no upstream, and the range then silently
  # returns nothing for every one of them.
  unpushed=$(git -C "$p" rev-list --count HEAD --not --remotes 2>/dev/null) || unpushed=""
  if [[ -z "$unpushed" ]]; then
    unpushed="?"
  fi
  R_UNPUSHED+=("$unpushed")

  if [[ -z "${T_HEAD[$idx]}" ]]; then
    T_HEAD[idx]=$(git -C "$p" rev-parse HEAD 2>/dev/null || printf '')
  fi
  if [[ -z "${T_BRANCH[$idx]}" ]]; then
    if branch_name=$(git -C "$p" symbolic-ref --quiet --short HEAD 2>/dev/null); then
      T_BRANCH[idx]="$branch_name"
    else
      T_BRANCH[idx]="(detached)"
    fi
  fi

  if [[ "$unpushed" == "0" ]]; then
    # Nothing unpushed means nothing to strand, and skipping the landed
    # computation here is what lets an empty patch-id set downstream mean ONLY
    # "something failed" rather than "the range was legitimately empty".
    R_LANDED+=("n/a")
    R_METHOD+=("none")
    R_BASE+=("")
    reason="nothing-unpushed"
  else
    classify_landed "$p"
    R_LANDED+=("$L_STATE")
    R_METHOD+=("$L_METHOD")
    R_BASE+=("$L_BASE")
    reason="$L_REASON"
  fi

  inprog=$(inprogress_of "$p")
  R_INPROGRESS+=("$inprog")
  if status_counts "$p"; then
    R_STAGED+=("$S_STAGED")
    R_UNSTAGED+=("$S_UNSTAGED")
    R_CONFLICTED+=("$S_CONFLICTED")
    R_UNTRACKED+=("$S_UNTRACKED")
  else
    R_STAGED+=("?")
    R_UNSTAGED+=("?")
    R_CONFLICTED+=("?")
    R_UNTRACKED+=("?")
    reason="${reason:+$reason; }status-unreadable: the working tree was not inspected"
  fi
  if [[ "$inprog" != "none" ]]; then
    reason="${reason:+$reason; }$inprog-in-progress: staged tree is that operation's own result, recomputable"
  fi
  R_REASON+=("$reason")
  idx=$((idx + 1))
done

assert_row_count "${#T_PATH[@]}" "${#R_LANDED[@]}" || exit 5

# Peers: another registered worktree holding the same commits, either at the same
# HEAD or at a descendant of it. A peer means removal does not make these commits
# unreachable, which is a different disposition from the same row without one.
PEERS=()
idx=0
while [[ $idx -lt ${#T_PATH[@]} ]]; do
  PEERS+=("")
  idx=$((idx + 1))
done
if [[ "$DO_PEERS" == "true" && ${#T_PATH[@]} -le 50 ]]; then
  idx=0
  while [[ $idx -lt ${#T_PATH[@]} ]]; do
    if [[ "${R_NOTGIT[$idx]}" == "yes" || -z "${T_HEAD[$idx]}" ]]; then
      idx=$((idx + 1))
      continue
    fi
    jdx=0
    while [[ $jdx -lt ${#T_PATH[@]} ]]; do
      if [[ $jdx -eq $idx || "${R_NOTGIT[$jdx]}" == "yes" || -z "${T_HEAD[$jdx]}" ]]; then
        jdx=$((jdx + 1))
        continue
      fi
      if [[ "${T_HEAD[$idx]}" == "${T_HEAD[$jdx]}" ]] ||
        git -C "${T_PATH[$idx]}" merge-base --is-ancestor "${T_HEAD[$idx]}" "${T_HEAD[$jdx]}" 2>/dev/null; then
        PEERS[idx]="${PEERS[$idx]:+${PEERS[$idx]},}${T_PATH[$jdx]}"
      fi
      jdx=$((jdx + 1))
    done
    idx=$((idx + 1))
  done
elif [[ "$DO_PEERS" == "true" ]]; then
  printf '%s: peer detection skipped — %s worktrees exceeds the 50-target ancestry budget\n' \
    "$PROG" "${#T_PATH[@]}" >&2
fi

printf 'path\tbranch\thead\tunpushed\tlanded\tmethod\tbase\tinprogress\tstaged\tunstaged\tconflicted\tuntracked\tpeers\trisk\treason\n'

emitted=0
idx=0
while [[ $idx -lt ${#T_PATH[@]} ]]; do
  reason="${R_REASON[$idx]}"
  if [[ "${R_NOTGIT[$idx]}" == "yes" ]]; then
    risk="notgit"
  elif [[ "${R_BARE[$idx]}" == "yes" ]]; then
    risk="bare"
  elif [[ "${R_LANDED[$idx]}" == "no" ]] && merged_ref "${T_BRANCH[$idx]}"; then
    # landed=no AND a merged PR on the same head ref: the base holds a later,
    # larger revision of this same work. Reporting it as stranded would read as
    # "do not remove" for a draft that was superseded on purpose.
    risk="superseded"
  elif [[ "${R_LANDED[$idx]}" == "no" ]]; then
    risk="STRANDED"
  elif [[ "${R_LANDED[$idx]}" == "?" ]]; then
    risk="UNKNOWN"
  elif [[ "${R_LANDED[$idx]}" == "yes" ]]; then
    risk="landed"
  elif [[ "${R_INPROGRESS[$idx]}" != "none" ]]; then
    risk="in-progress"
  elif [[ "${R_CONFLICTED[$idx]}" != "0" || "${R_UNSTAGED[$idx]}" != "0" || "${R_STAGED[$idx]}" != "0" ]]; then
    risk="dirty"
  else
    risk="ok"
  fi
  # Empty fields are emitted as `-`, never as nothing. A tab is IFS whitespace,
  # so bash's `read` COLLAPSES a run of them: a row with an empty `base` or
  # `peers` silently shifts every later column left, and the consumer reads the
  # reason string out of the risk column. Found by using this output from a
  # `while IFS=$'\t' read` loop, which is the most natural way to consume it and
  # the one this file's own callers are told to use.
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${T_PATH[$idx]:--}" "${T_BRANCH[$idx]:--}" "${T_HEAD[$idx]:0:12}" "${R_UNPUSHED[$idx]:--}" \
    "${R_LANDED[$idx]:--}" "${R_METHOD[$idx]:--}" "${R_BASE[$idx]:--}" "${R_INPROGRESS[$idx]:--}" \
    "${R_STAGED[$idx]:--}" "${R_UNSTAGED[$idx]:--}" "${R_CONFLICTED[$idx]:--}" "${R_UNTRACKED[$idx]:--}" \
    "${PEERS[$idx]:--}" "${risk:--}" "${reason:--}"
  emitted=$((emitted + 1))
  idx=$((idx + 1))
done

assert_row_count "${#T_PATH[@]}" "$emitted" || exit 5
exit 0

#!/usr/bin/env bash
# Multi-repo (fleet) clean for the selective tiers — run the single-repo
# caches / build / git tiers across a set of repositories behind ONE confirmation
# gate, with a separator-agnostic skip list and a per-repo outcome summary.
#
# This is a thin orchestrator. It runs no destructive command itself: every
# removal is delegated to the UNCHANGED single-repo child (clean-caches.sh,
# clean-build.sh, git-prune.sh), so every child gate — protection classes,
# submodule/reparse guards, the dry-run manifest + re-stat staleness guard — is
# reused verbatim. The batch layer adds only enumeration, path normalization,
# skip-matching, shared-object-store dedup, per-repo outcomes, and the single
# batch-wide dry-run -> confirm -> apply gate.
#
# Companion to git-tree-reset-batch.sh (the destructive `tree` tier's batch form);
# the selective tiers get the same fleet plumbing here. Shared plumbing lives in
# lib/batch-common.sh.
#
# Gated set (the fleet-snapshot-race fix): `--dry-run` writes a BATCH PLAN listing
# exactly the repos/common-dirs to act on, plus a per-repo child manifest for the
# caches/build tiers. `--apply --batch-plan <plan>` acts on THAT plan only — a
# repo that vanished after the dry-run applies idempotently (paths already gone),
# a repo that appeared is not in the plan so it is never touched. The plan is the
# fleet-level analogue of the child's per-repo manifest staleness guard.
#
# Usage:
#   clean-batch.sh --tier <caches|build|git|all> [--dry-run|--apply]
#                  [--repo DIR...]... [--repos-from FILE|-]...
#                  [--skip ENTRY]... [--skip-from FILE]...
#                  [--batch-plan FILE] [--help]
# Default: --dry-run.
#
# Exit: 0 ran to completion (skips/blocks are normal outcomes);
#       1 one or more repos failed mid-apply (a child rm failure);
#       2 usage/validation error (no tier, no repos, bad flag, apply without plan).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/batch-common.sh
source "$SCRIPT_DIR/lib/batch-common.sh"

usage() {
  cat <<'EOF'
clean-batch.sh — run the selective clean tiers across many repos behind one gate.

Usage:
  clean-batch.sh --tier <caches|build|git|all> [--dry-run|--apply]
                 [--repo DIR...]... [--repos-from FILE|-]...
                 [--skip ENTRY]... [--skip-from FILE]...
                 [--batch-plan FILE] [--help]

Default: --dry-run (inventory only; writes a batch plan, no mutations).

Tiers (mirror the single-repo tiers; `tree` is NOT batched here — use
git-tree-reset-batch.sh):
  caches  remove tool/linter caches per repo (clean-caches.sh)
  build   remove build output + caches per repo (clean-build.sh --include-caches)
  git     prune/gc each unique shared object store once (git-prune.sh)
  all     build + git per the single-repo `all` tier (no branch audit, no tree)

Repo sources (combine freely; deduped by canonical toplevel):
  --repo DIR...      one or more repositories (repeatable). Consumes every
                     consecutive non-flag path, so a shell glob (--repo
                     ~/repos/*) is ingested whole.
  --repos-from FILE  newline-delimited repo paths (FILE, or - for stdin; the way
                     `ghq list -p` output is ingested). Backslash paths are
                     normalized. Repeatable.

Skip list (separator-agnostic; entry = absolute path, owner/repo, or repo):
  --skip ENTRY       skip a repo (repeatable).
  --skip-from FILE   newline-delimited skip entries.

Gate:
  --dry-run          write a batch plan; print per-repo Outcome/Reason, a
                     `BatchPlan: <path>` line, and `Summary: repos=N planned=P
                     bytes=K` (gitdirs=G for git/all). NEVER mutates.
  --apply --batch-plan P
                     apply the gated plan P from a prior dry-run. Required: apply
                     without --batch-plan is a usage error (the gate is mandatory).
                     Prints `Summary: removed=N failed=M bytes=K` (plus gitdirs=G
                     for the git/all tiers). Exits non-zero if any repo failed.

Exit: 0 ran to completion; 1 a repo failed mid-apply; 2 usage error.
EOF
}

fail_usage() {
  echo "clean-batch.sh: $1" >&2
  exit 2
}

TIER=""
DRY_RUN=1
BATCH_PLAN_ARG=""
REPO_INPUTS=()
SKIP_INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --tier)
    [[ $# -ge 2 ]] || fail_usage "--tier requires caches|build|git|all"
    TIER="$2"
    shift
    ;;
  --dry-run) DRY_RUN=1 ;;
  --apply) DRY_RUN=0 ;;
  --batch-plan)
    [[ $# -ge 2 ]] || fail_usage "--batch-plan requires a file"
    BATCH_PLAN_ARG="$2"
    shift
    ;;
  --repo)
    # Consume every consecutive non-flag arg so a shell glob (`--repo ~/repos/*`)
    # arrives whole. Stops at the next `-`-prefixed flag or end of args.
    [[ $# -ge 2 && "$2" != -* ]] || fail_usage "--repo requires a directory"
    shift
    while [[ $# -gt 0 && "$1" != -* ]]; do
      REPO_INPUTS+=("$1")
      shift
    done
    continue
    ;;
  --repos-from)
    [[ $# -ge 2 ]] || fail_usage "--repos-from requires a file or -"
    batch_read_lines_into REPO_INPUTS "$2" || fail_usage "file not found: $2"
    shift
    ;;
  --skip)
    [[ $# -ge 2 ]] || fail_usage "--skip requires an entry"
    SKIP_INPUTS+=("$2")
    shift
    ;;
  --skip-from)
    [[ $# -ge 2 ]] || fail_usage "--skip-from requires a file"
    batch_read_lines_into SKIP_INPUTS "$2" || fail_usage "file not found: $2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) fail_usage "unknown arg '$1'" ;;
  esac
  shift
done

case "$TIER" in
caches | build | git | all) ;;
"") fail_usage "no tier (use --tier caches|build|git|all)" ;;
*) fail_usage "unknown tier '$TIER' (use caches|build|git|all)" ;;
esac

# Which selective child + flags a tier runs per repo. `all` and `build` both fold
# the caches tier into the build manifest (single-repo `build` = includes caches).
CACHES_CHILD="$SCRIPT_DIR/clean-caches.sh"
BUILD_CHILD="$SCRIPT_DIR/clean-build.sh"
GIT_CHILD="$SCRIPT_DIR/git-prune.sh"

# Does this tier run a per-repo manifest child (caches/build/all) and/or the git
# prune child (git/all)?
tier_has_manifest() { [[ "$TIER" == caches || "$TIER" == build || "$TIER" == all ]]; }
tier_has_git() { [[ "$TIER" == git || "$TIER" == all ]]; }

# Manifest child token written into the plan (apply picks the script from it).
manifest_child_token() { [[ "$TIER" == caches ]] && printf 'caches' || printf 'build'; }

# ---------------------------------------------------------------------------
# APPLY: consume the gated plan only (never re-enumerate).
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 0 ]]; then
  [[ -n "$BATCH_PLAN_ARG" ]] || fail_usage "--apply requires --batch-plan <path> from a prior --dry-run"
  [[ -f "$BATCH_PLAN_ARG" ]] || fail_usage "batch plan not found: $BATCH_PLAN_ARG"

  printf 'Fleet Clean (apply)\n'
  printf 'Tier: %s\n' "$TIER"
  printf '%s\n' '---'

  REMOVED=0
  FAILED=0
  BYTES=0
  GITDIRS=0

  while IFS=$'\t' read -r kind a b c; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
    REPO)
      # a=toplevel b=child-token c=manifest-path. Validate the whole record before
      # touching disk: a truncated or hand-edited plan line with an empty manifest
      # field would pass --manifest "" to the child, which reads that as "no
      # manifest" and RE-WALKS the live repo, removing artifacts never shown in the
      # gated dry-run. Fail closed — the batch contract is "apply the plan only".
      if [[ -z "$a" || ("$b" != caches && "$b" != build) || -z "$c" || ! -f "$c" ]]; then
        batch_emit "${a:-<empty>}" failed "malformed plan record (tier='$b' manifest='$c')"
        FAILED=$((FAILED + 1))
        continue
      fi
      if [[ ! -d "$a" ]]; then
        batch_emit "$a" skipped "vanished after dry-run (gone from fleet)"
        continue
      fi
      child="$CACHES_CHILD"
      extra=()
      if [[ "$b" == build ]]; then
        child="$BUILD_CHILD"
        extra=(--include-caches)
      fi
      out="$(cd "$a" && bash "$child" --apply --manifest "$c" "${extra[@]}" 2>&1)"
      rc=$?
      r="$(printf '%s\n' "$out" | sed -n 's/^Summary: //p' | head -1)"
      removed="$(sed -n 's/.*removed=\([0-9]*\).*/\1/p' <<<"$r")"
      failed="$(sed -n 's/.*failed=\([0-9]*\).*/\1/p' <<<"$r")"
      bytes="$(sed -n 's/.*bytes=\([0-9]*\).*/\1/p' <<<"$r")"
      removed="${removed:-0}"
      failed="${failed:-0}"
      bytes="${bytes:-0}"
      # Fail closed on a non-zero child that printed no parseable Summary (e.g. the
      # repo lost its .git between dry-run and apply — the child refuses with "not a
      # git repository" and exits before any Summary line). Without this the parsed
      # failed=0 would let the batch report failed=0 and exit 0 despite a real
      # failure. Count the child's own failed tally when it gave one, else one.
      if [[ "$failed" -eq 0 && "$rc" -ne 0 ]]; then failed=1; fi
      REMOVED=$((REMOVED + removed))
      FAILED=$((FAILED + failed))
      BYTES=$((BYTES + bytes))
      if [[ "$failed" -gt 0 ]]; then
        batch_emit "$a" failed "removed=$removed failed=$failed (child output on stderr)"
        printf '%s\n' "$out" >&2
      else
        batch_emit "$a" cleaned "removed=$removed bytes=$bytes"
      fi
      ;;
    GITDIR)
      # a=representative worktree toplevel (b=common-dir key, informational)
      GITDIRS=$((GITDIRS + 1))
      if [[ ! -d "$a" ]]; then
        batch_emit "$a" skipped "vanished after dry-run (gone from fleet)"
        continue
      fi
      out="$(cd "$a" && bash "$GIT_CHILD" --apply 2>&1)"
      rc=$?
      if [[ "$rc" -ne 0 ]]; then
        batch_emit "$a" failed "git prune failed (child output on stderr)"
        printf '%s\n' "$out" >&2
        FAILED=$((FAILED + 1))
      else
        batch_emit "$a" pruned "shared object store pruned once"
      fi
      ;;
    *) ;;
    esac
  done <"$BATCH_PLAN_ARG"

  if tier_has_git; then
    printf 'Summary: removed=%s failed=%s bytes=%s gitdirs=%s\n' "$REMOVED" "$FAILED" "$BYTES" "$GITDIRS"
  else
    printf 'Summary: removed=%s failed=%s bytes=%s\n' "$REMOVED" "$FAILED" "$BYTES"
  fi
  [[ "$FAILED" -eq 0 ]] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
# DRY-RUN: enumerate, plan, write the gated plan.
# ---------------------------------------------------------------------------
[[ ${#REPO_INPUTS[@]} -gt 0 ]] || fail_usage "no repos given (use --repo and/or --repos-from)"

batch_resolve_repos "${REPO_INPUTS[@]}"
batch_reset_gitdirs

# Batch plan + per-repo manifests live in one dir so they bundle and clean up
# together; honor an explicit --batch-plan location for a stable, resumable path.
if [[ -n "$BATCH_PLAN_ARG" ]]; then
  PLAN="$BATCH_PLAN_ARG"
  PLAN_DIR="$(dirname "$PLAN")"
else
  PLAN_DIR="$(mktemp -d 2>/dev/null)" || PLAN_DIR="${TMPDIR:-/tmp}/clean-batch.$$"
  PLAN="$PLAN_DIR/plan"
fi
# Create the plan dir for BOTH branches (an explicit --batch-plan may name a
# not-yet-existing parent) and verify the plan is actually writable — otherwise a
# failed redirect would leave no plan yet still print BatchPlan/Summary and exit 0.
mkdir -p "$PLAN_DIR" 2>/dev/null || fail_usage "cannot create batch-plan directory: $PLAN_DIR"
: >"$PLAN" 2>/dev/null || fail_usage "cannot write batch plan: $PLAN"

# Per-skip match tracking so a skip that protects nothing is surfaced loudly.
SKIP_HITS=()
for ((s = 0; s < ${#SKIP_INPUTS[@]}; s++)); do SKIP_HITS+=(0); done

REPOS=${#BATCH_TOPS[@]}
PLANNED=0
PLAN_BYTES=0
SKIPPED=0
BLOCKED=0

printf 'Fleet Clean (dry-run)\n'
printf 'Tier: %s\n' "$TIER"
printf 'Repos: %s\n' "$REPOS"
printf '%s\n' '---'

# Per-repo manifest name. The plan index (unique per repo in this batch) prefixes
# a sanitized key so two keys that differ only by punctuation the sanitizer
# collapses (e.g. `repo-a` vs `repo_a` -> both `repo_a`) never share a manifest —
# a collision would let the second dry-run truncate the first, dropping the first
# repo's planned artifacts from apply. The sanitized key stays for readability.
manifest_for() {
  local idx="$1" key="$2"
  printf '%s/%03d-%s.manifest' "$PLAN_DIR" "$idx" "${key//[^[:alnum:]]/_}"
}

for ((i = 0; i < ${#BATCH_TOPS[@]}; i++)); do
  top="${BATCH_TOPS[$i]}"
  key="${BATCH_KEYS[$i]}"

  # 1. Skip list (separator-agnostic).
  matched=""
  for ((s = 0; s < ${#SKIP_INPUTS[@]}; s++)); do
    if clean_skip_matches "$key" "${SKIP_INPUTS[$s]}"; then
      matched="${SKIP_INPUTS[$s]}"
      SKIP_HITS[s]=1
    fi
  done
  if [[ -n "$matched" ]]; then
    batch_emit "$top" skipped "skip-list ($matched)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  reason_parts=()

  # 2. Manifest tier (caches/build/all): run the child dry-run, capture its
  #    manifest + planned bytes, record a REPO plan line.
  if tier_has_manifest; then
    manifest="$(manifest_for "$i" "$key")"
    child="$CACHES_CHILD"
    extra=()
    tok="$(manifest_child_token)"
    if [[ "$tok" == build ]]; then
      child="$BUILD_CHILD"
      extra=(--include-caches)
    fi
    out="$(cd "$top" && bash "$child" --dry-run --manifest "$manifest" "${extra[@]}" 2>&1)"
    rc=$?
    # Fail closed on a non-zero child dry-run (repo lost .git after resolution, or
    # the child refused an unwritable / pre-existing non-manifest path). Otherwise
    # the missing Summary would default planned/bytes to 0, still write a REPO plan
    # line, and report a clean preview — gating an incomplete plan. Block the repo
    # (no plan line) so apply never touches it.
    if [[ "$rc" -ne 0 ]]; then
      batch_emit "$top" blocked "$tok dry-run failed (child exit $rc — not planned)"
      printf '%s\n' "$out" >&2
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    r="$(printf '%s\n' "$out" | sed -n 's/^Summary: //p' | head -1)"
    planned="$(sed -n 's/.*planned=\([0-9]*\).*/\1/p' <<<"$r")"
    bytes="$(sed -n 's/.*bytes=\([0-9]*\).*/\1/p' <<<"$r")"
    planned="${planned:-0}"
    bytes="${bytes:-0}"
    PLANNED=$((PLANNED + planned))
    PLAN_BYTES=$((PLAN_BYTES + bytes))
    printf 'REPO\t%s\t%s\t%s\n' "$top" "$tok" "$manifest" >>"$PLAN"
    reason_parts+=("$tok: $planned path(s), $(clean_human_size "$bytes")")
  fi

  # 3. Git tier (git/all): record the repo's unique shared object store once. The
  #    first-seen worktree is the plan's representative to cd into; if only THAT
  #    worktree vanishes before apply while a live sibling remains, the prune is
  #    reported skipped (deferred, not lost — non-destructive, idempotent, and a
  #    re-run over the live siblings picks a new representative). See clean-batch.md.
  if tier_has_git; then
    if batch_add_gitdir "$top"; then
      k="${BATCH_GITDIR_KEYS[${#BATCH_GITDIR_KEYS[@]} - 1]}"
      printf 'GITDIR\t%s\t%s\n' "$top" "$k" >>"$PLAN"
      reason_parts+=("git: shared object store (new)")
    else
      reason_parts+=("git: shared object store (deduped with a sibling worktree)")
    fi
  fi

  reason=""
  for rp in "${reason_parts[@]}"; do
    [[ -n "$reason" ]] && reason+="; "
    reason+="$rp"
  done
  batch_emit "$top" would-clean "$reason"
done

# Invalid inputs reported as blocked outcomes.
for ((i = 0; i < ${#BATCH_INVALID[@]}; i++)); do
  batch_emit "${BATCH_INVALID[$i]}" blocked "${BATCH_INVALID_REASONS[$i]}"
  BLOCKED=$((BLOCKED + 1))
done

# Surface skip entries that matched nothing — a typo can never silently fail to
# protect a repo.
for ((s = 0; s < ${#SKIP_INPUTS[@]}; s++)); do
  if [[ "${SKIP_HITS[$s]}" -eq 0 ]]; then
    printf 'UnmatchedSkip: %s\n' "${SKIP_INPUTS[$s]}"
  fi
done

printf 'BatchPlan: %s\n' "$PLAN"
if tier_has_git; then
  printf 'Summary: repos=%s planned=%s bytes=%s skipped=%s blocked=%s gitdirs=%s\n' \
    "$REPOS" "$PLANNED" "$PLAN_BYTES" "$SKIPPED" "$BLOCKED" "${#BATCH_GITDIR_KEYS[@]}"
else
  printf 'Summary: repos=%s planned=%s bytes=%s skipped=%s blocked=%s\n' \
    "$REPOS" "$PLANNED" "$PLAN_BYTES" "$SKIPPED" "$BLOCKED"
fi
exit 0

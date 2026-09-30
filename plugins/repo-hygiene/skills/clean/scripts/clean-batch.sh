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
#   clean-batch.sh --tier <scan|caches|build|git|all> [--dry-run|--apply]
#                  [--repo DIR...]... [--repos-from FILE|-]...
#                  [--skip ENTRY]... [--skip-from FILE]...
#                  [--batch-plan FILE] [--list-paths-max N] [--help]
# --batch-plan FILE also works with --dry-run: it fixes the plan path (default: a
# durable per-repo-set dir under ${CLAUDE_PLUGIN_DATA:-~/.claude/plugins/data/repo-hygiene}).
# Default: --dry-run. `--tier scan` is read-only (scan.sh per repo): it writes no
# plan, and --apply / --batch-plan with it are usage errors.
#
# Exit: 0 ran to completion (skips/blocks are normal outcomes);
#       1 one or more repos failed mid-apply (a child rm failure, or a structurally
#         corrupt plan record failed closed);
#       2 usage/validation error (no tier, no repos, bad flag, apply without plan,
#         --apply or --batch-plan with --tier scan, or a plan whose records do
#         not match the requested --tier).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/batch-common.sh
source "$SCRIPT_DIR/lib/batch-common.sh"

usage() {
  cat <<'EOF'
clean-batch.sh — run the selective clean tiers across many repos behind one gate.

Usage:
  clean-batch.sh --tier <scan|caches|build|git|all> [--dry-run|--apply]
                 [--repo DIR...]... [--repos-from FILE|-]...
                 [--skip ENTRY]... [--skip-from FILE]...
                 [--batch-plan FILE] [--list-paths-max N] [--help]

Default: --dry-run (inventory only; writes a batch plan, no mutations).

Tiers (mirror the single-repo tiers; `tree` is NOT batched here — use
git-tree-reset-batch.sh):
  scan    read-only inventory per repo (scan.sh); writes no plan, and --apply /
          --batch-plan are usage errors. Prints `Outcome: scanned` per repo and
          `Summary: repos=N planned=0 bytes=K skipped=S blocked=B`, K the summed
          `Total reclaimable`.
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
  --dry-run          write a batch plan; print per-repo Outcome/Reason (a repo
                     with nothing to remove reports `nothing-to-do`), a
                     `Repo | Outcome | Paths | Bytes` table, the planned paths
                     per repo (largest first, read from the same manifests
                     apply consumes; capped, with an `N more, see plan file:
                     <path>` tail), a `BatchPlan: <path>` line, and `Summary:
                     repos=N planned=P bytes=K` (gitdirs=G for git/all). NEVER
                     mutates.
  --batch-plan FILE  with --dry-run, write the plan to FILE (a stable path)
                     instead of the default. The default is one directory per
                     tier and repo set under ${CLAUDE_PLUGIN_DATA} (else
                     ~/.claude/plugins/data/repo-hygiene): a repeat dry-run of
                     the same set replaces its previous plan and manifests.
  --list-paths-max N per-repo cap on the dry-run path listing (default 20;
                     0 lists none).
  --apply --batch-plan P
                     apply the gated plan P from a prior dry-run. Required: apply
                     without --batch-plan is a usage error (the gate is mandatory).
                     P must have been built for the SAME --tier: a plan whose
                     records the requested tier does not authorize (e.g. a build
                     plan under --tier caches, or a GITDIR record under a non-git
                     tier) is refused before anything is removed. Prints `Summary:
                     removed=N failed=M bytes=K` (plus gitdirs=G for the git/all
                     tiers). Exits non-zero if any repo failed.

Exit: 0 ran to completion; 1 a repo failed mid-apply; 2 usage error.
EOF
}

fail_usage() {
  echo "clean-batch.sh: $1" >&2
  exit 2
}

TIER=""
DRY_RUN=1
APPLY_GIVEN=0
BATCH_PLAN_ARG=""
LIST_MAX=20
REPO_INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --tier)
    [[ $# -ge 2 ]] || fail_usage "--tier requires scan|caches|build|git|all"
    TIER="$2"
    shift
    ;;
  --dry-run) DRY_RUN=1 ;;
  --apply)
    DRY_RUN=0
    APPLY_GIVEN=1
    ;;
  --batch-plan)
    [[ $# -ge 2 ]] || fail_usage "--batch-plan requires a file"
    BATCH_PLAN_ARG="$2"
    shift
    ;;
  --list-paths-max)
    [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || fail_usage "--list-paths-max requires a non-negative integer"
    LIST_MAX=$((10#$2))
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
    BATCH_SKIP_INPUTS+=("$2")
    shift
    ;;
  --skip-from)
    [[ $# -ge 2 ]] || fail_usage "--skip-from requires a file"
    batch_read_lines_into BATCH_SKIP_INPUTS "$2" || fail_usage "file not found: $2"
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
scan | caches | build | git | all) ;;
"") fail_usage "no tier (use --tier scan|caches|build|git|all)" ;;
*) fail_usage "unknown tier '$TIER' (use scan|caches|build|git|all)" ;;
esac

if [[ "$TIER" == scan ]]; then
  [[ "$APPLY_GIVEN" -eq 0 ]] || fail_usage "--tier scan is read-only: --apply is not accepted"
  [[ -z "$BATCH_PLAN_ARG" ]] || fail_usage "--tier scan writes no plan: --batch-plan is not accepted"
fi

# Which selective child + flags a tier runs per repo. `all` and `build` both fold
# the caches tier into the build manifest (single-repo `build` = includes caches).
CACHES_CHILD="$SCRIPT_DIR/clean-caches.sh"
BUILD_CHILD="$SCRIPT_DIR/clean-build.sh"
GIT_CHILD="$SCRIPT_DIR/git-prune.sh"

# select_manifest_child <token>: set `child` (the script to run) and `extra`
# (its tier flags) from a manifest record's token. One spelling for the plan
# writer and the apply loop, so a `build` record cannot fold caches on one side
# and not the other.
select_manifest_child() {
  child="$CACHES_CHILD"
  extra=()
  if [[ "$1" == build ]]; then
    child="$BUILD_CHILD"
    extra=(--include-caches)
  fi
}

# Does this tier run a per-repo manifest child (caches/build/all) and/or the git
# prune child (git/all)?
tier_has_manifest() { [[ "$TIER" == caches || "$TIER" == build || "$TIER" == all ]]; }
tier_has_git() { [[ "$TIER" == git || "$TIER" == all ]]; }

# Manifest child token written into the plan (apply picks the script from it).
manifest_child_token() { [[ "$TIER" == caches ]] && printf 'caches' || printf 'build'; }

# The REPO manifest token the requested tier AUTHORIZES at apply, or empty for a
# tier that authorizes no REPO record (git). Distinct from manifest_child_token,
# which never returns empty and would wrongly authorize a build REPO record under
# --tier git: authorization must fail closed for a tier that plans no REPO work.
tier_repo_token() {
  case "$TIER" in
  caches) printf 'caches' ;;
  build | all) printf 'build' ;;
  *) printf '' ;;
  esac
}

# Is a plan record structurally well-formed — does it carry the fields the dry-run
# writer emits? Shared by the tier pre-scan and the apply loop so both agree on
# what counts as a record: a truncated or hand-edited line (a GITDIR naming no
# representative worktree, a REPO naming no manifest) must neither satisfy the
# `all` both-kinds-present requirement nor reach a child. Field SHAPE only —
# whether the referenced manifest still EXISTS is deliberately not judged here,
# because a manifest that vanished after the dry-run is a per-record runtime
# failure the apply loop reports (exit 1), not a plan built for the wrong tier, and
# judging it in the pre-scan would refuse the whole apply with the wrong diagnosis.
plan_repo_record_wellformed() {
  local top="$1" token="$2" manifest="$3"
  [[ -n "$top" && ("$token" == caches || "$token" == build) && -n "$manifest" ]]
}
# A GITDIR record's only load-bearing field is the representative worktree toplevel
# to cd into; its common-dir key is informational.
plan_gitdir_record_wellformed() { [[ -n "$1" ]]; }

# Child `Summary: …` parsing, shared by the apply and dry-run loops so both read a
# child's tallies the same way. summary_line <child-output> extracts the first
# Summary line; summary_field <name> <summary-line> pulls one numeric `<name>=<n>`
# field out of it, or nothing when the field is absent (callers default to 0).
summary_line() { sed -n 's/^Summary: //p' <<<"$1" | head -1; }
summary_field() { sed -n "s/.*$1=\([0-9]*\).*/\1/p" <<<"$2"; }

# ---------------------------------------------------------------------------
# SCAN: read-only inventory per repo; no plan, nothing to gate.
# ---------------------------------------------------------------------------
if [[ "$TIER" == scan ]]; then
  [[ ${#REPO_INPUTS[@]} -gt 0 ]] || fail_usage "no repos given (use --repo and/or --repos-from)"
  batch_resolve_repos "${REPO_INPUTS[@]}"
  batch_reset_skip_hits

  SKIPPED=0
  BLOCKED=0
  SCAN_BYTES=0
  printf 'Fleet Clean (scan)\n'
  printf 'Tier: scan\n'
  printf 'Repos: %s\n' "${#BATCH_TOPS[@]}"
  printf '%s\n' '---'
  for ((i = 0; i < ${#BATCH_TOPS[@]}; i++)); do
    top="${BATCH_TOPS[$i]}"
    printf 'Progress: %s/%s %s\n' "$((i + 1))" "${#BATCH_TOPS[@]}" "$top" >&2
    if batch_skip_match "${BATCH_KEYS[$i]}"; then
      batch_emit "$top" skipped "skip-list ($BATCH_SKIP_MATCHED)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    out="$(cd "$top" && bash "$SCRIPT_DIR/scan.sh" 2>&1)"
    rc=$?
    bytes="$(sed -n 's/^Total reclaimable: \([0-9]*\)$/\1/p' <<<"$out" | head -1)"
    # scan.sh exits 0 even when it fails and then prints no total; a missing total
    # is a blocked repo, never a silent 0.
    if [[ "$rc" -ne 0 || -z "$bytes" ]]; then
      batch_emit "$top" blocked "scan failed (child exit $rc, no total)"
      printf '%s\n' "$out" >&2
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    paths="$(grep -c '^Path: ' <<<"$out" || true)"
    SCAN_BYTES=$((SCAN_BYTES + bytes))
    batch_emit "$top" scanned "$paths path(s), $(clean_human_size "$bytes") reclaimable"
  done
  for ((i = 0; i < ${#BATCH_INVALID[@]}; i++)); do
    batch_emit "${BATCH_INVALID[$i]}" blocked "${BATCH_INVALID_REASONS[$i]}"
    BLOCKED=$((BLOCKED + 1))
  done
  batch_report_unmatched_skips
  printf 'Summary: repos=%s planned=0 bytes=%s skipped=%s blocked=%s\n' \
    "${#BATCH_TOPS[@]}" "$SCAN_BYTES" "$SKIPPED" "$BLOCKED"
  exit 0
fi

# ---------------------------------------------------------------------------
# APPLY: consume the gated plan only (never re-enumerate).
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 0 ]]; then
  [[ -n "$BATCH_PLAN_ARG" ]] || fail_usage "--apply requires --batch-plan <path> from a prior --dry-run"
  [[ -f "$BATCH_PLAN_ARG" ]] || fail_usage "batch plan not found: $BATCH_PLAN_ARG"

  # Tier-authorization pre-scan: refuse the whole apply — before the banner, before
  # touching any disk — if the plan carries a record the requested --tier does not
  # authorize. A plan built for a broader tier (e.g. a build plan, whose REPO
  # records fold caches) applied under a narrower --tier caches would otherwise
  # execute the broader gated content while the banner names the narrower tier —
  # scope misrepresentation. Atomic refusal (exit 2, nothing removed, no banner)
  # makes that structurally impossible. A malformed/unrecognized token is NOT judged
  # here; the apply loop fails those closed per-record (exit 1) as structural
  # corruption, a different error class from a well-formed plan for the wrong tier.
  #
  # Authorization alone is only half the match: `all` authorizes BOTH record kinds,
  # so a narrower plan (a `build` plan with no GITDIR records, or a `git` plan with
  # no REPO records) would pass every per-record test and then apply only part of
  # the requested tier while the banner named `all`. The same misrepresentation,
  # from the other direction. So the plan's record-kind SET must also be the set the
  # tier plans: `all` requires both kinds present. Presence is required only when
  # the plan carries records at all — a fleet where every repo was skipped or
  # blocked plans nothing for either kind, and an empty plan removes nothing under
  # any tier.
  #
  # Presence is satisfied only by a STRUCTURALLY WELL-FORMED record. A truncated
  # line names no target, so counting it would let a narrower plan clear the `all`
  # requirement on a record that removes nothing — apply would print `Tier: all` and
  # `gitdirs=1` while performing no Git cleanup, the same misrepresentation this
  # pre-scan exists to close. The record KIND is still authorization-judged
  # regardless of its fields: a GITDIR line under a non-git tier is a wrong-tier
  # plan however malformed it is.
  PLAN_HAS_REPO=0
  PLAN_HAS_GITDIR=0
  while IFS=$'\t' read -r kind a b c; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
    REPO)
      [[ "$b" == caches || "$b" == build ]] || continue
      if [[ "$b" != "$(tier_repo_token)" ]]; then
        fail_usage "plan record does not match --tier $TIER: a '$b' REPO record is not authorized (plan built for a different tier?). Re-run --dry-run --tier $TIER."
      fi
      plan_repo_record_wellformed "$a" "$b" "$c" && PLAN_HAS_REPO=1
      ;;
    GITDIR)
      tier_has_git || fail_usage "plan record does not match --tier $TIER: a GITDIR record requires --tier git or all (plan built for a different tier?). Re-run --dry-run --tier $TIER."
      plan_gitdir_record_wellformed "$a" && PLAN_HAS_GITDIR=1
      ;;
    *) ;;
    esac
  done <"$BATCH_PLAN_ARG"

  if [[ "$TIER" == all && "$PLAN_HAS_REPO" -ne "$PLAN_HAS_GITDIR" ]]; then
    if [[ "$PLAN_HAS_GITDIR" -eq 0 ]]; then
      fail_usage "plan record does not match --tier all: the plan carries no well-formed GITDIR record, so applying it would skip the git tier entirely (plan built for a different tier?). Re-run --dry-run --tier all."
    fi
    fail_usage "plan record does not match --tier all: the plan carries no well-formed REPO record, so applying it would skip the build tier entirely (plan built for a different tier?). Re-run --dry-run --tier all."
  fi

  printf 'Fleet Clean (apply)\n'
  printf 'Tier: %s\n' "$TIER"
  printf '%s\n' '---'

  REMOVED=0
  FAILED=0
  BYTES=0
  GITDIRS=0
  APPLY_INDEX=0

  while IFS=$'\t' read -r kind a b c; do
    [[ -n "$kind" ]] || continue
    APPLY_INDEX=$((APPLY_INDEX + 1))
    printf 'Progress: apply %s %s\n' "$APPLY_INDEX" "${a:-<empty>}" >&2
    case "$kind" in
    REPO)
      # a=toplevel b=child-token c=manifest-path. Validate the whole record before
      # touching disk: a truncated or hand-edited plan line with an empty manifest
      # field would pass --manifest "" to the child, which reads that as "no
      # manifest" and RE-WALKS the live repo, removing artifacts never shown in the
      # gated dry-run. Fail closed — the batch contract is "apply the plan only".
      # The field-shape half is the pre-scan's predicate; the manifest must also
      # still be on disk by the time apply reads it.
      if ! plan_repo_record_wellformed "$a" "$b" "$c" || [[ ! -f "$c" ]]; then
        batch_emit "${a:-<empty>}" failed "malformed plan record (tier='$b' manifest='$c')"
        FAILED=$((FAILED + 1))
        continue
      fi
      if [[ ! -d "$a" ]]; then
        batch_emit "$a" skipped "vanished after dry-run (gone from fleet)"
        continue
      fi
      select_manifest_child "$b"
      out="$(cd "$a" && bash "$child" --apply --manifest "$c" "${extra[@]}" 2>&1)"
      rc=$?
      r="$(summary_line "$out")"
      removed="$(summary_field removed "$r")"
      failed="$(summary_field failed "$r")"
      bytes="$(summary_field bytes "$r")"
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
      # a=representative worktree toplevel (b=common-dir key, informational).
      # Validate before counting, as the REPO arm does: a truncated line names no
      # representative, so an empty `a` would count toward gitdirs= and then read as
      # `! -d` — reporting a prune "skipped (vanished)" for a store that never had a
      # target, and a gitdirs= tally larger than the prunes actually attempted. Fail
      # closed as structural corruption instead.
      if ! plan_gitdir_record_wellformed "$a"; then
        batch_emit "<empty>" failed "malformed plan record (GITDIR names no representative worktree)"
        FAILED=$((FAILED + 1))
        continue
      fi
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
# The default dir is keyed to the tier, the sorted repo set and the skip list, so a repeat dry-run
# of the same set lands on the same path and replaces its stale plan and manifests.
if [[ -n "$BATCH_PLAN_ARG" ]]; then
  PLAN="$BATCH_PLAN_ARG"
  PLAN_DIR="$(dirname "$PLAN")"
else
  DATA_DIR="${CLAUDE_PLUGIN_DATA:-}"
  if [[ -z "$DATA_DIR" ]]; then
    [[ -n "${HOME:-}" ]] || fail_usage "cannot place the batch plan: neither CLAUDE_PLUGIN_DATA nor HOME is set (use --batch-plan FILE)"
    DATA_DIR="$HOME/.claude/plugins/data/repo-hygiene"
  fi
  SET_KEY="$({
    printf 'repo\t%s\n' "${BATCH_TOPS[@]}"
    [[ ${#BATCH_SKIP_INPUTS[@]} -eq 0 ]] || printf 'skip\t%s\n' "${BATCH_SKIP_INPUTS[@]}"
  } | LC_ALL=C sort | cksum | cut -d' ' -f1)"
  PLAN_DIR="$DATA_DIR/clean-batch/$TIER-$SET_KEY"
  PLAN="$PLAN_DIR/plan"
  mkdir -p "$PLAN_DIR" 2>/dev/null || fail_usage "cannot create batch-plan directory: $PLAN_DIR"
  rm -f "$PLAN" "$PLAN_DIR"/*.manifest
fi
# Refuse to truncate an unrelated file: a typo'd --batch-plan path must not
# silently destroy user data. An existing target is overwritten only when it is
# already a batch plan (every non-empty line a REPO/GITDIR tab-record) — the
# resumable case — mirroring the child --manifest non-manifest-overwrite guard.
if [[ -n "$BATCH_PLAN_ARG" && -e "$PLAN" ]]; then
  [[ -f "$PLAN" ]] || fail_usage "--batch-plan target is not a regular file: $PLAN"
  if ! awk -F'\t' 'NF && $1 != "REPO" && $1 != "GITDIR" { exit 1 }' "$PLAN"; then
    fail_usage "refusing to overwrite a file that is not a batch plan (typo'd --batch-plan?): $PLAN"
  fi
fi
# Create the plan dir for BOTH branches (an explicit --batch-plan may name a
# not-yet-existing parent) and verify the plan is actually writable — otherwise a
# failed redirect would leave no plan yet still print BatchPlan/Summary and exit 0.
mkdir -p "$PLAN_DIR" 2>/dev/null || fail_usage "cannot create batch-plan directory: $PLAN_DIR"
: >"$PLAN" 2>/dev/null || fail_usage "cannot write batch plan: $PLAN"

# Per-skip match tracking so a skip that protects nothing is surfaced loudly.
batch_reset_skip_hits

REPOS=${#BATCH_TOPS[@]}
PLANNED=0
PLAN_BYTES=0
SKIPPED=0
BLOCKED=0
ROW_TOPS=()
ROW_OUTCOMES=()
ROW_PATHS=()
ROW_BYTES=()
LIST_TOPS=()
LIST_MANIFESTS=()
# add_row <top> <outcome> <paths> <bytes>: one summary-table row per repo.
add_row() {
  ROW_TOPS+=("$1")
  ROW_OUTCOMES+=("$2")
  ROW_PATHS+=("$3")
  ROW_BYTES+=("$4")
}

printf 'Fleet Clean (dry-run)\n'
printf 'Tier: %s\n' "$TIER"
printf 'Repos: %s\n' "$REPOS"
# One preflight run, not once per repo: host-global facts (processes, IDE) plus
# recent builds under every batch repository. The git-only tier does not delete
# caches or build output, so it does not pay this walk. Apply does not run it
# again: the dry-run output is what the confirmation gate reads.
if tier_has_manifest && ((${#BATCH_TOPS[@]} > 0)); then
  printf 'PreflightScope: batch-repositories\n'
  if preflight_out="$(bash "$SCRIPT_DIR/preflight.sh" "${BATCH_TOPS[@]}" 2>&1)"; then
    printf '%s\n' "$preflight_out"
  else
    printf 'PreflightError: preflight.sh exited non-zero\n'
  fi
fi
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
  printf 'Progress: %s/%s %s\n' "$((i + 1))" "${#BATCH_TOPS[@]}" "$top" >&2

  # 1. Skip list (separator-agnostic).
  if batch_skip_match "$key"; then
    batch_emit "$top" skipped "skip-list ($BATCH_SKIP_MATCHED)"
    add_row "$top" skipped 0 0
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  reason_parts=()
  planned=0
  bytes=0
  new_gitdir=0

  # 2. Manifest tier (caches/build/all): run the child dry-run, capture its
  #    manifest + planned bytes, record a REPO plan line.
  if tier_has_manifest; then
    manifest="$(manifest_for "$i" "$key")"
    tok="$(manifest_child_token)"
    select_manifest_child "$tok"
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
      add_row "$top" blocked 0 0
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    r="$(summary_line "$out")"
    planned="$(summary_field planned "$r")"
    bytes="$(summary_field bytes "$r")"
    planned="${planned:-0}"
    bytes="${bytes:-0}"
    PLANNED=$((PLANNED + planned))
    PLAN_BYTES=$((PLAN_BYTES + bytes))
    printf 'REPO\t%s\t%s\t%s\n' "$top" "$tok" "$manifest" >>"$PLAN"
    if [[ "$planned" -gt 0 && -s "$manifest" ]]; then
      LIST_TOPS+=("$top")
      LIST_MANIFESTS+=("$manifest")
    fi
    reason_parts+=("$tok: $planned path(s), $(clean_human_size "$bytes")")
  fi

  # 3. Git tier (git/all): record the repo's unique shared object store once. The
  #    first-seen worktree is the plan's representative to cd into; if only THAT
  #    worktree vanishes before apply while a live sibling remains, the prune is
  #    reported skipped (deferred, not lost — non-destructive, idempotent, and a
  #    re-run over the live siblings picks a new representative). See clean-batch.md.
  if tier_has_git; then
    if batch_add_gitdir "$top"; then
      new_gitdir=1
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
  # A manifest-tier repo with nothing planned that adds no new object store has
  # nothing for apply to remove. A new store is a real prune/gc plan.
  outcome=would-clean
  if [[ "$planned" -eq 0 && "$bytes" -eq 0 && "$new_gitdir" -eq 0 ]]; then outcome=nothing-to-do; fi
  batch_emit "$top" "$outcome" "$reason"
  add_row "$top" "$outcome" "$planned" "$bytes"
done

# Invalid inputs reported as blocked outcomes.
for ((i = 0; i < ${#BATCH_INVALID[@]}; i++)); do
  batch_emit "${BATCH_INVALID[$i]}" blocked "${BATCH_INVALID_REASONS[$i]}"
  add_row "${BATCH_INVALID[$i]}" blocked 0 0
  BLOCKED=$((BLOCKED + 1))
done

# Surface skip entries that matched nothing — a typo can never silently fail to
# protect a repo.
batch_report_unmatched_skips

printf 'Repo | Outcome | Paths | Bytes\n'
for ((i = 0; i < ${#ROW_TOPS[@]}; i++)); do
  printf '%s | %s | %s | %s\n' "${ROW_TOPS[$i]}" "${ROW_OUTCOMES[$i]}" "${ROW_PATHS[$i]}" "$(clean_human_size "${ROW_BYTES[$i]}")"
done

# Planned paths per repo, read from the manifests apply consumes, so the gate
# names exactly the set shown. Largest first; manifest lines are class<TAB>bytes<TAB>rel.
if [[ "$LIST_MAX" -gt 0 ]]; then
  for ((i = 0; i < ${#LIST_TOPS[@]}; i++)); do
    total="$(grep -c . "${LIST_MANIFESTS[$i]}")"
    printf 'Paths: %s\n' "${LIST_TOPS[$i]}"
    LC_ALL=C sort -t$'\t' -k2,2nr "${LIST_MANIFESTS[$i]}" | head -n "$LIST_MAX" |
      while IFS=$'\t' read -r cls bytes rel; do
        printf '  %s | %s | %s\n' "$rel" "$cls" "$(clean_human_size "${bytes:-0}")"
      done
    if [[ "$total" -gt "$LIST_MAX" ]]; then
      printf '  %s more, see plan file: %s\n' "$((total - LIST_MAX))" "$PLAN"
    fi
  done
fi

printf 'BatchPlan: %s\n' "$PLAN"
if tier_has_git; then
  printf 'Summary: repos=%s planned=%s bytes=%s skipped=%s blocked=%s gitdirs=%s\n' \
    "$REPOS" "$PLANNED" "$PLAN_BYTES" "$SKIPPED" "$BLOCKED" "${#BATCH_GITDIR_KEYS[@]}"
else
  printf 'Summary: repos=%s planned=%s bytes=%s skipped=%s blocked=%s\n' \
    "$REPOS" "$PLANNED" "$PLAN_BYTES" "$SKIPPED" "$BLOCKED"
fi
exit 0

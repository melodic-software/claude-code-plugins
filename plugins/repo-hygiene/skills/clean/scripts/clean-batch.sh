#!/usr/bin/env bash
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
# shellcheck source=lib/run-marker.sh
source "$SCRIPT_DIR/lib/run-marker.sh"

usage() {
  cat <<'EOF'
clean-batch.sh — run the selective clean tiers across many repos behind one gate.

Usage:
  clean-batch.sh --tier <scan|caches|build|git|all> [--dry-run|--apply]
                 [--repo DIR...]... [--repos-from FILE|-]... [--fleet]
                 [--owner OWNER]... [--skip ENTRY]... [--skip-from FILE]...
                 [--batch-plan FILE] [--data-dir DIR] [--list-paths-max N] [--help]

Default: --dry-run (inventory only; writes a batch plan, no mutations).

Tiers (mirror the single-repo tiers; `tree` is not batched here — use
git-tree-reset-batch.sh):
  scan    read-only inventory per repo (scan.sh); writes no plan, and --apply /
          --batch-plan are usage errors. Prints `Outcome: scanned` per repo and
          `Summary: repos=N planned=0 bytes=K skipped=S blocked=B`, K the summed
          `Total reclaimable`.
  caches  remove tool/linter caches per repo (clean-caches.sh)
  build   remove build output + caches per repo (clean-build.sh --include-caches)
  git     prune/gc each unique shared object store once (git-prune.sh)
  all     build + git per the single-repo `all` tier (no branch audit, no tree)

Repo sources (combine freely; deduped by canonical toplevel. With --fleet or
--owner, also by origin URL: the first clone that is not skip-listed is kept,
each other is `skipped duplicate of <path>`. Without either, two clones of one
origin are both kept):
  --repo DIR...      one or more repositories (repeatable). Consumes every
                     consecutive non-flag path, so a shell glob (--repo
                     ~/repos/*) is ingested whole.
  --repos-from FILE  newline-delimited repo paths (FILE, or - for stdin; the way
                     `ghq list -p` output is ingested). Backslash paths are
                     normalized. Repeatable.
  --fleet            every `ghq list -p` repo (when ghq resolves) plus the chezmoi
                     source repo (when chezmoi resolves and its source is a git repo),
                     and it dedupes clones of one origin URL across the whole set.
  --owner OWNER      the --fleet repos whose origin is <host>/OWNER/<name> (owner
                     case-insensitive on github.com); dedupes clones like --fleet.
                     Repeatable.

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
                     repos=N planned=P bytes=K` (git/all append gitdirs=G
                     git_bytes=B; all also appends caches_bytes=C build_bytes=D).
                     The git tier counts prunable worktrees, plus loose objects
                     and garbage when `git gc --auto` would run (above gc.auto
                     or gc.autoPackLimit). Never mutates.
  --batch-plan FILE  with --dry-run, write the plan to FILE (a stable path)
                     instead of the default. The default is a new run
                     directory under one durable directory per tier, repo set
                     and skip list in the plugin data dir (--data-dir): a
                     repeat dry-run never replaces a plan you already
                     confirmed, and run directories older than 14 days are
                     removed.
  --data-dir DIR     the repo-hygiene plugin data dir that holds the default
                     plan. The skill passes it; without it an inherited
                     CLAUDE_PLUGIN_DATA is used only when its last path
                     segment names repo-hygiene (another plugin's hook can
                     export its own dir under that name), else
                     ~/.claude/plugins/data/repo-hygiene.
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

plugin_data_dir() {
  if [[ -n "$DATA_DIR_ARG" ]]; then
    # shellcheck disable=SC2016 # the literal, unexpanded token is what is matched
    case "$DATA_DIR_ARG" in
    *'${'* | *'<plugin-data>'*) fail_usage "--data-dir got an unsubstituted placeholder: $DATA_DIR_ARG" ;;
    *) ;;
    esac
    printf '%s\n' "$DATA_DIR_ARG"
    return 0
  fi
  if run_marker_data_dir_ours "${CLAUDE_PLUGIN_DATA:-}"; then
    printf '%s\n' "$CLAUDE_PLUGIN_DATA"
    return 0
  fi
  [[ -n "${HOME:-}" ]] || fail_usage "cannot place the batch plan: no --data-dir and HOME is not set (use --batch-plan FILE)"
  printf '%s\n' "$HOME/.claude/plugins/data/repo-hygiene"
}

TIER=""
DRY_RUN=1
APPLY_GIVEN=0
BATCH_PLAN_ARG=""
DATA_DIR_ARG=""
LIST_MAX=20
PLAN_RETAIN_DAYS=14
REPO_INPUTS=()
FLEET=0

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
  --data-dir)
    [[ $# -ge 2 ]] || fail_usage "--data-dir requires a directory"
    DATA_DIR_ARG="$2"
    shift
    ;;
  --list-paths-max)
    [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || fail_usage "--list-paths-max requires a non-negative integer"
    LIST_MAX=$((10#$2))
    shift
    ;;
  --repo)
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
  --fleet)
    FLEET=1
    batch_discover_fleet REPO_INPUTS
    ;;
  --owner)
    [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || fail_usage "--owner requires an owner"
    FLEET=1
    batch_discover_owner REPO_INPUTS "$2"
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

CACHES_CHILD="$SCRIPT_DIR/clean-caches.sh"
BUILD_CHILD="$SCRIPT_DIR/clean-build.sh"
GIT_CHILD="$SCRIPT_DIR/git-prune.sh"

select_manifest_child() {
  child="$CACHES_CHILD"
  extra=()
  if [[ "$1" == build ]]; then
    child="$BUILD_CHILD"
    extra=(--include-caches)
  fi
}

tier_has_manifest() { [[ "$TIER" == caches || "$TIER" == build || "$TIER" == all ]]; }
tier_has_git() { [[ "$TIER" == git || "$TIER" == all ]]; }

manifest_child_token() { [[ "$TIER" == caches ]] && printf 'caches' || printf 'build'; }

tier_repo_token() {
  case "$TIER" in
  caches) printf 'caches' ;;
  build | all) printf 'build' ;;
  *) printf '' ;;
  esac
}

plan_repo_record_wellformed() {
  local top="$1" token="$2" manifest="$3"
  [[ -n "$top" && ("$token" == caches || "$token" == build) && -n "$manifest" ]]
}
plan_gitdir_record_wellformed() { [[ -n "$1" ]]; }

summary_line() { sed -n 's/^Summary: //p' <<<"$1" | head -1; }
summary_field() {
  local v
  v="$(sed -n "s/.*$1=\([0-9]*\).*/\1/p" <<<"$2")"
  printf '%s\n' "${v:-0}"
}

if [[ "$TIER" == scan ]]; then
  [[ ${#REPO_INPUTS[@]} -gt 0 ]] || fail_usage "no repos given (use --repo, --repos-from, --owner and/or --fleet)"
  batch_resolve_repos "${REPO_INPUTS[@]}"
  if [[ "$FLEET" -eq 1 ]]; then batch_dedupe_clones; fi
  batch_reset_skip_hits

  SKIPPED=${#BATCH_DUPS[@]}
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
  batch_emit_dups
  for ((i = 0; i < ${#BATCH_INVALID[@]}; i++)); do
    batch_emit "${BATCH_INVALID[$i]}" blocked "${BATCH_INVALID_REASONS[$i]}"
    BLOCKED=$((BLOCKED + 1))
  done
  batch_report_unmatched_skips
  printf 'Summary: repos=%s planned=0 bytes=%s skipped=%s blocked=%s\n' \
    "${#BATCH_TOPS[@]}" "$SCAN_BYTES" "$SKIPPED" "$BLOCKED"
  exit 0
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  [[ -n "$BATCH_PLAN_ARG" ]] || fail_usage "--apply requires --batch-plan <path> from a prior --dry-run"
  [[ -f "$BATCH_PLAN_ARG" ]] || fail_usage "batch plan not found: $BATCH_PLAN_ARG"

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

  printf 'Summary: removed=%s failed=%s bytes=%s' "$REMOVED" "$FAILED" "$BYTES"
  if tier_has_git; then printf ' gitdirs=%s' "$GITDIRS"; fi
  printf '\n'
  [[ "$FAILED" -eq 0 ]] || exit 1
  exit 0
fi

[[ ${#REPO_INPUTS[@]} -gt 0 ]] || fail_usage "no repos given (use --repo, --repos-from, --owner and/or --fleet)"

batch_resolve_repos "${REPO_INPUTS[@]}"
if [[ "$FLEET" -eq 1 ]]; then batch_dedupe_clones; fi
batch_reset_gitdirs

if [[ -n "$BATCH_PLAN_ARG" ]]; then
  PLAN="$BATCH_PLAN_ARG"
  PLAN_DIR="$(dirname "$PLAN")"
else
  DATA_DIR="$(plugin_data_dir)" || exit 2
  SET_KEY="$({
    printf 'repo\t%s\n' "${BATCH_TOPS[@]}"
    [[ ${#BATCH_SKIP_INPUTS[@]} -eq 0 ]] || printf 'skip\t%s\n' "${BATCH_SKIP_INPUTS[@]}"
  } | LC_ALL=C sort | cksum | cut -d' ' -f1)"
  SET_DIR="$DATA_DIR/clean-batch/$TIER-$SET_KEY"
  mkdir -p "$SET_DIR" 2>/dev/null || fail_usage "cannot create batch-plan directory: $SET_DIR"
  find "$SET_DIR" -maxdepth 1 -type d -name 'run.*' -mtime +"$PLAN_RETAIN_DAYS" -exec rm -rf {} + 2>/dev/null || true
  PLAN_DIR="$(mktemp -d "$SET_DIR/run.XXXXXX" 2>/dev/null)" || fail_usage "cannot create batch-plan directory under: $SET_DIR"
  PLAN="$PLAN_DIR/plan"
fi
if [[ -n "$BATCH_PLAN_ARG" && -e "$PLAN" ]]; then
  [[ -f "$PLAN" ]] || fail_usage "--batch-plan target is not a regular file: $PLAN"
  if ! awk -F'\t' 'NF && $1 != "REPO" && $1 != "GITDIR" { exit 1 }' "$PLAN"; then
    fail_usage "refusing to overwrite a file that is not a batch plan (typo'd --batch-plan?): $PLAN"
  fi
fi
mkdir -p "$PLAN_DIR" 2>/dev/null || fail_usage "cannot create batch-plan directory: $PLAN_DIR"
: >"$PLAN" 2>/dev/null || fail_usage "cannot write batch plan: $PLAN"

batch_reset_skip_hits

REPOS=${#BATCH_TOPS[@]}
PLANNED=0
PLAN_BYTES=0
CACHES_BYTES=0
BUILD_BYTES=0
GIT_BYTES=0
SKIPPED=${#BATCH_DUPS[@]}
BLOCKED=0
ROW_TOPS=()
ROW_OUTCOMES=()
ROW_PATHS=()
ROW_BYTES=()
LIST_TOPS=()
LIST_MANIFESTS=()
add_row() {
  ROW_TOPS+=("$1")
  ROW_OUTCOMES+=("$2")
  ROW_PATHS+=("$3")
  ROW_BYTES+=("$4")
}

printf 'Fleet Clean (dry-run)\n'
printf 'Tier: %s\n' "$TIER"
printf 'Repos: %s\n' "$REPOS"
if tier_has_manifest && ((${#BATCH_TOPS[@]} > 0)); then
  printf 'PreflightScope: batch-repositories\n'
  if preflight_out="$(bash "$SCRIPT_DIR/preflight.sh" "${BATCH_TOPS[@]}" 2>&1)"; then
    printf '%s\n' "$preflight_out"
  else
    printf 'PreflightError: preflight.sh exited non-zero\n'
  fi
fi
printf '%s\n' '---'

# git gc --auto acts only above gc.auto loose objects (default 6700) or gc.autoPackLimit packs (default 50):
# https://git-scm.com/docs/git-config
git_plan_measure() {
  local k v wt auto limit n=0 kib=0 loose=0 packs=0 garbage=0 kib_loose=0 kib_garbage=0
  while IFS=': ' read -r k v; do
    case "$k" in
    count) loose=$v ;;
    packs) packs=$v ;;
    garbage) garbage=$v ;;
    size) kib_loose=$v ;;
    size-garbage) kib_garbage=$v ;;
    *) ;;
    esac
  done < <(git -C "$1" count-objects -v 2>/dev/null)
  auto="$(git -C "$1" config --type=int --get gc.auto 2>/dev/null)" || auto=6700
  limit="$(git -C "$1" config --type=int --get gc.autoPackLimit 2>/dev/null)" || limit=50
  if ((auto > 0)) && { ((loose > auto)) || ((limit > 0 && packs > limit)); }; then
    n=$((loose + garbage))
    kib=$((kib_loose + kib_garbage))
  fi
  wt="$(git -C "$1" worktree prune --dry-run -v 2>&1 | grep -c .)"
  printf '%s %s\n' "$((n + wt))" "$((kib * 1024))"
}

manifest_for() {
  local idx="$1" key="$2"
  printf '%s/%03d-%s.manifest' "$PLAN_DIR" "$idx" "${key//[^[:alnum:]]/_}"
}

for ((i = 0; i < ${#BATCH_TOPS[@]}; i++)); do
  top="${BATCH_TOPS[$i]}"
  key="${BATCH_KEYS[$i]}"
  printf 'Progress: %s/%s %s\n' "$((i + 1))" "${#BATCH_TOPS[@]}" "$top" >&2

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

  if tier_has_manifest; then
    manifest="$(manifest_for "$i" "$key")"
    tok="$(manifest_child_token)"
    select_manifest_child "$tok"
    out="$(cd "$top" && bash "$child" --dry-run --manifest "$manifest" "${extra[@]}" 2>&1)"
    rc=$?
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
    PLANNED=$((PLANNED + planned))
    PLAN_BYTES=$((PLAN_BYTES + bytes))
    read -r cb bb < <(awk -F'\t' '$1=="caches"{c+=$2} $1=="build"{b+=$2} END{print c+0, b+0}' "$manifest" 2>/dev/null)
    CACHES_BYTES=$((CACHES_BYTES + ${cb:-0}))
    BUILD_BYTES=$((BUILD_BYTES + ${bb:-0}))
    printf 'REPO\t%s\t%s\t%s\n' "$top" "$tok" "$manifest" >>"$PLAN"
    if [[ "$planned" -gt 0 && -s "$manifest" ]]; then
      LIST_TOPS+=("$top")
      LIST_MANIFESTS+=("$manifest")
    fi
    reason_parts+=("$tok: $planned path(s), $(clean_human_size "$bytes")")
  fi

  if tier_has_git; then
    if batch_add_gitdir "$top"; then
      new_gitdir=1
      k="${BATCH_GITDIR_KEYS[${#BATCH_GITDIR_KEYS[@]} - 1]}"
      printf 'GITDIR\t%s\t%s\n' "$top" "$k" >>"$PLAN"
      read -r gpaths gbytes < <(git_plan_measure "$top")
      planned=$((planned + gpaths))
      bytes=$((bytes + gbytes))
      PLANNED=$((PLANNED + gpaths))
      PLAN_BYTES=$((PLAN_BYTES + gbytes))
      GIT_BYTES=$((GIT_BYTES + gbytes))
      reason_parts+=("git: shared object store (new): $gpaths item(s) counted, $(clean_human_size "$gbytes"); remote prune not measured")
    else
      reason_parts+=("git: shared object store (deduped with a sibling worktree)")
    fi
  fi

  printf -v reason '%s; ' "${reason_parts[@]}"
  reason="${reason%; }"
  outcome=would-clean
  if [[ "$planned" -eq 0 && "$bytes" -eq 0 && "$new_gitdir" -eq 0 ]]; then outcome=nothing-to-do; fi
  batch_emit "$top" "$outcome" "$reason"
  add_row "$top" "$outcome" "$planned" "$bytes"
done

batch_emit_dups
for ((i = 0; i < ${#BATCH_DUPS[@]}; i++)); do
  add_row "${BATCH_DUPS[$i]}" skipped 0 0
done

for ((i = 0; i < ${#BATCH_INVALID[@]}; i++)); do
  batch_emit "${BATCH_INVALID[$i]}" blocked "${BATCH_INVALID_REASONS[$i]}"
  add_row "${BATCH_INVALID[$i]}" blocked 0 0
  BLOCKED=$((BLOCKED + 1))
done

batch_report_unmatched_skips

printf 'Repo | Outcome | Paths | Bytes\n'
for ((i = 0; i < ${#ROW_TOPS[@]}; i++)); do
  printf '%s | %s | %s | %s\n' "${ROW_TOPS[$i]}" "${ROW_OUTCOMES[$i]}" "${ROW_PATHS[$i]}" "$(clean_human_size "${ROW_BYTES[$i]}")"
done

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
printf 'Summary: repos=%s planned=%s bytes=%s skipped=%s blocked=%s' \
  "$REPOS" "$PLANNED" "$PLAN_BYTES" "$SKIPPED" "$BLOCKED"
if tier_has_git; then
  printf ' gitdirs=%s' "${#BATCH_GITDIR_KEYS[@]}"
  if [[ "$TIER" == all ]]; then printf ' caches_bytes=%s build_bytes=%s' "$CACHES_BYTES" "$BUILD_BYTES"; fi
  printf ' git_bytes=%s' "$GIT_BYTES"
fi
printf '\n'
exit 0

#!/usr/bin/env bash
# Move canonical checkouts onto the remote default branch and fast-forward.
# Bare invocation prints a plan and changes nothing. --apply mutates after one
# confirmation, or immediately with --yes. Never resets, never force-pushes.
# Divergent work is parked in a linked worktree. Non-fast-forward, dubious
# ownership, and a partial stash apply are skipped and reported.
set -uo pipefail

APPLY=0
YES=0
PARK_ROOT=""
RESOLVER=""
CREATE=""
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --apply) APPLY=1; shift ;;
  --yes) YES=1; shift ;;
  --park-root)
    [[ $# -ge 2 ]] || { echo "sync-fleet.sh: --park-root needs a directory" >&2; exit 2; }
    PARK_ROOT="$2"
    shift 2
    ;;
  --worktree-create)
    [[ $# -ge 2 ]] || { echo "sync-fleet.sh: --worktree-create needs a path" >&2; exit 2; }
    CREATE="$2"
    shift 2
    ;;
  *) ARGS+=("$1"); shift ;;
  esac
done

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
RESOLVER="${SCRIPT_DIR}/../../../scripts/resolve-fleet-scope.sh"
if [[ -z "$CREATE" ]]; then
  monorepo="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
  if [[ -f "$monorepo/plugins/source-control/scripts/worktree-create.sh" ]]; then
    CREATE="$monorepo/plugins/source-control/scripts/worktree-create.sh"
  fi
fi
if [[ -z "$PARK_ROOT" ]]; then
  PARK_ROOT="${HOME:-/tmp}/.claude/fleet-park"
fi

scope_out="$(bash "$RESOLVER" ${ARGS[@]+"${ARGS[@]}"} )" || {
  rc=$?
  if [[ "$rc" -eq 3 ]]; then
    echo "sync-fleet.sh: no repository scope (pass --repo, a fleet config, or run inside a work tree)" >&2
  fi
  exit "$rc"
}
mapfile -t REPOS <<<"$scope_out"

plan_line() { printf 'plan\t%s\t%s\t%s\n' "$1" "$2" "$3"; }
report_line() { printf 'result\t%s\t%s\t%s\n' "$1" "$2" "$3"; }

default_branch_of() {
  local repo="$1" line
  line="$(git -C "$repo" ls-remote --symref origin HEAD 2>/dev/null | awk 'NR==1 && $1=="ref:" { sub(/^refs\/heads\//, "", $2); print $2; exit }' || true)"
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line"
    return 0
  fi
  line="$(git -C "$repo" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  line="${line#refs/remotes/origin/}"
  line="${line%$'\r'}"
  printf '%s\n' "$line"
}

sanitize() {
  local name="$1"
  name="${name//\//-}"
  name="${name//[^A-Za-z0-9._-]/-}"
  printf '%s\n' "${name:0:48}"
}

if [[ "$APPLY" -eq 0 ]]; then
  for repo in "${REPOS[@]}"; do
    branch="$(default_branch_of "$repo" || true)"
    current="$(git -C "$repo" branch --show-current 2>/dev/null || true)"
    dirty="$(git -C "$repo" status --porcelain 2>/dev/null || true)"
    action="ff-pull"
    [[ -n "$dirty" || ( -n "$current" && "$current" != "$branch" ) ]] && action="park-then-ff-pull"
    plan_line "$repo" "$action" "default=${branch:-unknown} current=${current:-detached}"
  done
  echo "dry-run: pass --apply to mutate (one confirmation, or --yes)"
  exit 0
fi

if [[ "$YES" -ne 1 ]]; then
  if [[ ! -r /dev/tty ]]; then
    echo "sync-fleet.sh: --apply needs a terminal confirmation or --yes" >&2
    exit 2
  fi
  printf 'Apply fleet sync to %s repo(s)? Type yes: ' "${#REPOS[@]}" >/dev/tty
  IFS= read -r answer </dev/tty || answer=""
  [[ "$answer" == "yes" ]] || { echo "sync-fleet.sh: not confirmed" >&2; exit 2; }
fi

mkdir -p "$PARK_ROOT"

sync_one() {
  local repo="$1" err current dirty branch slug wt
  err="$(mktemp)"
  if ! git -C "$repo" status --porcelain >/dev/null 2>"$err"; then
    if grep -q "dubious ownership" "$err"; then
      report_line "$repo" "skip" "dubious ownership"
    else
      report_line "$repo" "skip" "git status failed"
    fi
    rm -f "$err"
    return 0
  fi
  rm -f "$err"
  branch="$(default_branch_of "$repo")"
  if [[ -z "$branch" ]]; then
    report_line "$repo" "skip" "no origin HEAD symref"
    return 0
  fi
  current="$(git -C "$repo" branch --show-current 2>/dev/null || true)"
  dirty="$(git -C "$repo" status --porcelain 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    if ! git -C "$repo" stash push -u -m "fleet-sync" >/dev/null 2>&1; then
      report_line "$repo" "skip" "stash failed"
      return 0
    fi
  fi
  if [[ "$current" != "$branch" && -n "$current" ]]; then
    if ! git -C "$repo" switch "$branch" >/dev/null 2>&1; then
      report_line "$repo" "skip" "could not switch to $branch"
      return 0
    fi
    slug="$(sanitize "$current")"
    if [[ -n "$CREATE" ]]; then
      if ! wt="$(bash "$CREATE" --repo-dir "$repo" --name "$slug" --existing-branch "$current" --root "$PARK_ROOT" 2>/dev/null)"; then
        report_line "$repo" "skip" "could not park $current"
        return 0
      fi
    else
      wt="$PARK_ROOT/$slug"
      if ! git -C "$repo" worktree add "$wt" "$current" >/dev/null 2>&1; then
        report_line "$repo" "skip" "could not park $current"
        return 0
      fi
    fi
    if [[ -n "$dirty" ]]; then
      if ! git -C "$wt" stash pop >/dev/null 2>&1; then
        report_line "$repo" "skip" "partial stash apply in $wt"
        return 0
      fi
    fi
  elif [[ -n "$dirty" ]]; then
    slug="park-$(date -u +%Y%m%dT%H%M%SZ)"
    if [[ -n "$CREATE" ]]; then
      if ! wt="$(bash "$CREATE" --repo-dir "$repo" --name "$slug" --root "$PARK_ROOT" --base-ref head 2>/dev/null)"; then
        report_line "$repo" "skip" "could not park dirty default branch"
        return 0
      fi
    else
      wt="$PARK_ROOT/$slug"
      if ! git -C "$repo" worktree add -b "$slug" "$wt" HEAD >/dev/null 2>&1; then
        report_line "$repo" "skip" "could not park dirty default branch"
        return 0
      fi
    fi
    if ! git -C "$wt" stash pop >/dev/null 2>&1; then
      report_line "$repo" "skip" "partial stash apply in $wt"
      return 0
    fi
  fi
  if ! git -C "$repo" pull --ff-only origin "$branch" >/dev/null 2>&1; then
    report_line "$repo" "skip" "not a fast-forward"
    return 0
  fi
  report_line "$repo" "ok" "on $branch"
}

for repo in "${REPOS[@]}"; do
  sync_one "$repo"
done
exit 0

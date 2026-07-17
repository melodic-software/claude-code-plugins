#!/usr/bin/env bash
# Guarded removal of an orphaned repo clone or leftover directory under the
# ghq root — the whole-directory deletion the selective tiers never perform
# (they remove artifacts inside a repo; this removes the repo/dir itself,
# e.g. a local clone whose upstream repository was deleted).
#
# Usage:
#   remove-path.sh <target> [--dry-run] [--apply] [--allow-unpushed]
#                  [--include-secrets] [--root <dir>]
# Default: --dry-run
#
# Guards (all evaluated before any mutation):
#   - target must be an existing directory strictly inside the resolved root
#     (ghq root by default; --root overrides), never the root itself
#   - symlink / reparse-point targets are refused (deletion would traverse)
#   - a linked-worktree target (.git file) is refused — `git worktree remove`
#     owns that lifecycle
#   - a git-repo target is refused while it has: uncommitted changes, stash
#     entries, registered linked worktrees, or ignored secret-class files
#     (.env*, *.local.json/.jsonc/.md — override with --include-secrets)
#   - unpushed work (branch ahead of upstream, branch with no upstream, or a
#     detached HEAD) blocks the apply unless --allow-unpushed
#
# Exit: 0 success; 1 target does not exist; 2 usage/validation error;
#       3 blocked (dirty / stash / worktrees / secrets); 4 unpushed work.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1
ALLOW_UNPUSHED=0
INCLUDE_SECRETS=0
ROOT_OVERRIDE=""
TARGET=""

usage() {
  cat <<'EOF'
remove-path.sh — guarded removal of an orphaned clone or leftover directory
under the ghq root.

Usage:
  remove-path.sh <target> [--dry-run] [--apply] [--allow-unpushed]
                 [--include-secrets] [--root <dir>] [--help]

Default: --dry-run (print guard results and the planned removal only).
--apply:           execute the removal after all guards pass.
--allow-unpushed:  proceed despite unpushed branches or a detached HEAD.
--include-secrets: proceed despite ignored secret-class files (UNRECOVERABLE).
--root <dir>:      containment root (default: ghq root).

Output labels:
  Target / Root / Kind: <repo|dir>
  TrackedDirty / StashCount / WorktreeCount / UnpushedRefs / SecretsCount
  Blocked: <reason or none>
  Planned / Applied: rm -rf <target>

Exit: 0 success; 1 target missing; 2 usage/validation; 3 blocked; 4 unpushed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=1 ;;
  --apply) DRY_RUN=0 ;;
  --allow-unpushed) ALLOW_UNPUSHED=1 ;;
  --include-secrets) INCLUDE_SECRETS=1 ;;
  --root)
    shift
    [[ $# -gt 0 ]] || { echo "remove-path.sh: --root needs a value" >&2; exit 2; }
    ROOT_OVERRIDE="$1"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    echo "remove-path.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  *)
    [[ -z "$TARGET" ]] || { echo "remove-path.sh: multiple targets given" >&2; exit 2; }
    TARGET="$1"
    ;;
  esac
  shift
done

if [[ -z "$TARGET" ]]; then
  echo "remove-path.sh: no target given" >&2
  exit 2
fi

ROOT="$ROOT_OVERRIDE"
if [[ -z "$ROOT" ]]; then
  ROOT="$(git config ghq.root 2>/dev/null | tr -d '\r')"
fi
if [[ -z "$ROOT" ]] && command -v ghq >/dev/null 2>&1; then
  ROOT="$(ghq root 2>/dev/null | tr -d '\r')"
fi
if [[ -z "$ROOT" ]]; then
  echo "remove-path.sh: no containment root (no ghq root; pass --root)" >&2
  exit 2
fi

# Normalize both sides to forward-slash absolute paths for containment checks.
norm() { local p; p="$(cd "$1" 2>/dev/null && pwd)" || return 1; printf '%s' "${p//\\//}"; }

if [[ -L "$TARGET" ]]; then
  echo "remove-path.sh: target is a symlink/reparse point — refusing" >&2
  exit 2
fi
if [[ ! -d "$TARGET" ]]; then
  echo "remove-path.sh: target does not exist: $TARGET" >&2
  exit 1
fi

ROOT_ABS="$(norm "$ROOT")" || { echo "remove-path.sh: root does not exist: $ROOT" >&2; exit 2; }
TARGET_ABS="$(norm "$TARGET")" || exit 1

if [[ "$TARGET_ABS" == "$ROOT_ABS" ]]; then
  echo "remove-path.sh: target is the containment root itself — refusing" >&2
  exit 2
fi
if [[ "$TARGET_ABS" != "$ROOT_ABS"/* ]]; then
  echo "remove-path.sh: target is outside the containment root ($ROOT_ABS)" >&2
  exit 2
fi

if [[ -f "$TARGET_ABS/.git" ]]; then
  echo "remove-path.sh: target is a linked worktree — use git worktree remove" >&2
  exit 2
fi

KIND=dir
TRACKED_DIRTY=0
STASH_COUNT=0
WORKTREE_COUNT=0
UNPUSHED_REFS=0
SECRETS_COUNT=0

if [[ -d "$TARGET_ABS/.git" ]]; then
  KIND=repo
  TRACKED_DIRTY="$(git -C "$TARGET_ABS" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  STASH_COUNT="$(git -C "$TARGET_ABS" stash list 2>/dev/null | wc -l | tr -d ' ')"
  # Count beyond the main entry: any linked worktree must be removed first.
  WORKTREE_COUNT="$(git -C "$TARGET_ABS" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)"

  while IFS=' ' read -r ref upstream; do
    [[ -z "$ref" ]] && continue
    if [[ -z "$upstream" ]]; then
      UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
      continue
    fi
    ahead="$(git -C "$TARGET_ABS" rev-list --count "$upstream..$ref" 2>/dev/null | tr -d ' ')"
    [[ "${ahead:-0}" -gt 0 ]] && UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
  done < <(git -C "$TARGET_ABS" for-each-ref refs/heads --format='%(refname:short) %(upstream:short)' 2>/dev/null | tr -d '\r')

  if [[ -z "$(git -C "$TARGET_ABS" branch --show-current 2>/dev/null | tr -d '\r')" ]] &&
    git -C "$TARGET_ABS" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    UNPUSHED_REFS=$((UNPUSHED_REFS + 1)) # detached HEAD — commits may be unreachable elsewhere
  fi

  while IFS= read -r ignored; do
    [[ -z "$ignored" ]] && continue
    case "$ignored" in
    .env* | */.env* | *.local.json | *.local.jsonc | *.local.md)
      SECRETS_COUNT=$((SECRETS_COUNT + 1))
      ;;
    *) ;;
    esac
  done < <(git -C "$TARGET_ABS" ls-files --others --ignored --exclude-standard 2>/dev/null | tr -d '\r')
fi

printf 'Target: %s\n' "$TARGET_ABS"
printf 'Root: %s\n' "$ROOT_ABS"
printf 'Kind: %s\n' "$KIND"
printf 'TrackedDirty: %s\n' "$TRACKED_DIRTY"
printf 'StashCount: %s\n' "$STASH_COUNT"
printf 'WorktreeCount: %s\n' "$WORKTREE_COUNT"
printf 'UnpushedRefs: %s\n' "$UNPUSHED_REFS"
printf 'SecretsCount: %s\n' "$SECRETS_COUNT"

BLOCKED=none
EXIT=0
if [[ "$TRACKED_DIRTY" -gt 0 ]]; then
  BLOCKED="dirty ($TRACKED_DIRTY uncommitted change(s))"
  EXIT=3
elif [[ "$STASH_COUNT" -gt 0 ]]; then
  BLOCKED="stash ($STASH_COUNT entry(ies))"
  EXIT=3
elif [[ "$WORKTREE_COUNT" -gt 1 ]]; then
  BLOCKED="linked-worktrees ($((WORKTREE_COUNT - 1)) registered — remove them first)"
  EXIT=3
elif [[ "$SECRETS_COUNT" -gt 0 && "$INCLUDE_SECRETS" -eq 0 ]]; then
  BLOCKED="secrets ($SECRETS_COUNT ignored secret-class file(s) — pass --include-secrets to discard)"
  EXIT=3
elif [[ "$UNPUSHED_REFS" -gt 0 && "$ALLOW_UNPUSHED" -eq 0 ]]; then
  BLOCKED="unpushed ($UNPUSHED_REFS ref(s) with unpushed work — pass --allow-unpushed to discard)"
  EXIT=4
fi
printf 'Blocked: %s\n' "$BLOCKED"

if [[ "$BLOCKED" != none ]]; then
  printf 'Planned: none\n'
  exit "$EXIT"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'Planned: rm -rf %s\n' "$TARGET_ABS"
  exit 0
fi

rm -rf "$TARGET_ABS"
if [[ -e "$TARGET_ABS" ]]; then
  echo "remove-path.sh: removal incomplete (locked / in use): $TARGET_ABS" >&2
  exit 1
fi
printf 'Applied: rm -rf %s\n' "$TARGET_ABS"
exit 0

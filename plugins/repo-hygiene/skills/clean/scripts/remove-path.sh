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
#     (ghq root by default; --root overrides), never the root itself; both sides
#     resolve symlinked components physically (pwd -P) so a symlinked/junction
#     ancestor under the root cannot slip an outside target past the containment
#     check, and the target must share the root's filesystem device so an
#     ancestor bind mount to another filesystem cannot escape it either. Residual
#     (out of the path-based model): a same-device bind mount is not detectable
#     here.
#   - symlink / reparse-point targets are refused (bash -L plus a Windows
#     fsutil reparse query — deletion would traverse)
#   - a linked-worktree target (.git file) is refused — `git worktree remove`
#     owns that lifecycle
#   - a plain-dir target still holding nested git repos — a normal clone, a
#     submodule/linked worktree, or a bare mirror — is refused; each child owns
#     its own removal and state inspection
#   - a repo target (normal or bare) is refused while it has: uncommitted
#     changes, stash entries, registered linked worktrees, or ignored files in
#     the SECRETS preserve class (CLEAN_TREE_PRESERVE_SECRETS — override with
#     --include-secrets); a plain-dir target is scanned for the same SECRETS
#     class. Git state that cannot be inspected (corrupt index, unreadable
#     object store) fails closed to a refusal rather than reading as clean
#   - unpushed work (branch or local tag ahead of or missing its upstream,
#     unresolvable upstream, or a detached HEAD) blocks the apply unless
#     --allow-unpushed
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
  Target / Root / Kind: <repo|bare-repo|dir>
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
    [[ $# -gt 0 ]] || {
      echo "remove-path.sh: --root needs a value" >&2
      exit 2
    }
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
    [[ -z "$TARGET" ]] || {
      echo "remove-path.sh: multiple targets given" >&2
      exit 2
    }
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
# pwd -P resolves symlinked intermediate components physically on BOTH sides, so
# a symlinked ancestor under the root (e.g. $root/link -> /outside) cannot slip a
# target past containment while rm -rf would still traverse the link outside.
norm() {
  local p
  p="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  printf '%s' "${p//\\//}"
}

if clean_path_is_reparse_point "$TARGET"; then
  echo "remove-path.sh: target is a symlink/reparse point — refusing" >&2
  exit 2
fi
if [[ ! -d "$TARGET" ]]; then
  echo "remove-path.sh: target does not exist: $TARGET" >&2
  exit 1
fi

ROOT_ABS="$(norm "$ROOT")" || {
  echo "remove-path.sh: root does not exist: $ROOT" >&2
  exit 2
}
TARGET_ABS="$(norm "$TARGET")" || exit 1

if [[ "$TARGET_ABS" == "$ROOT_ABS" ]]; then
  echo "remove-path.sh: target is the containment root itself — refusing" >&2
  exit 2
fi
if [[ "$TARGET_ABS" != "$ROOT_ABS"/* ]]; then
  echo "remove-path.sh: target is outside the containment root ($ROOT_ABS)" >&2
  exit 2
fi

# Physical resolution above defeats symlinked/junction ancestors, but a bind
# mount (Linux `mount --bind`) is not a symlink — pwd -P cannot see through it,
# so $root/external -> a bind mount of /outside would still pass the path check
# while rm -rf traverses to the outside filesystem. Require the target to sit on
# the same filesystem device as the root; a differing device is a mount crossing
# the root boundary. Residual, out of the path-based containment model: a
# SAME-device bind mount shares the root's device and is not caught here. Skipped
# when stat cannot report a device (the pwd -P + path check still apply).
dev_of() { stat -c '%d' "$1" 2>/dev/null || stat -f '%d' "$1" 2>/dev/null; }
root_dev="$(dev_of "$ROOT_ABS")"
target_dev="$(dev_of "$TARGET_ABS")"
if [[ -n "$root_dev" && -n "$target_dev" && "$root_dev" != "$target_dev" ]]; then
  echo "remove-path.sh: target is on a different filesystem/mount than the root — refusing" >&2
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

# Structural bare-repo detection (HEAD + objects/ + refs/ at the top level) —
# deliberately not `rev-parse --is-bare-repository`, which walks upward and
# would misclassify a plain subdirectory of some enclosing repo.
if [[ -f "$TARGET_ABS/HEAD" && -d "$TARGET_ABS/objects" && -d "$TARGET_ABS/refs" ]]; then
  KIND=bare-repo
elif [[ -d "$TARGET_ABS/.git" ]]; then
  KIND=repo
fi

# A plain-dir target is removed wholesale, but the repo guards below inspect only
# the target itself — never its descendants. A leftover parent (a ghq owner dir,
# any folder still holding child clones/submodules/linked worktrees/bare mirrors)
# would take their unpushed commits, stashes, and secrets down with it unseen.
# Refuse and defer to per-child removal rather than guess each child's state.
if [[ "$KIND" == dir ]]; then
  # Normal repos + submodules/linked worktrees: any descendant named .git
  # (a repo's .git directory, or a submodule/worktree's .git file).
  nested="$(find "$TARGET_ABS" -mindepth 2 -name .git -print -quit 2>/dev/null)"
  # Bare repos leave no .git entry, so detect them structurally the same way
  # KIND detection does: a descendant dir holding HEAD + objects/ + refs/.
  if [[ -z "$nested" ]]; then
    while IFS= read -r -d '' head_file; do
      d="${head_file%/HEAD}"
      if [[ -d "$d/objects" && -d "$d/refs" ]]; then
        nested="$d"
        break
      fi
    done < <(find "$TARGET_ABS" -mindepth 2 -name HEAD -type f -print0 2>/dev/null)
  fi
  if [[ -n "$nested" ]]; then
    echo "remove-path.sh: target contains nested git repos — inspect and remove them individually first" >&2
    exit 2
  fi
fi

if [[ "$KIND" != dir ]]; then
  if [[ "$KIND" == repo ]]; then
    # Fail closed: a working tree or stash that cannot be inspected (corrupt
    # index, unreadable object store) must block, never read as clean. Capture
    # first and check the exit status — a `| wc -l` pipeline would swallow the
    # non-zero exit and return 0. printf '%s\n' re-adds the single trailing
    # newline that command substitution stripped so the line count is exact.
    if ! dirty_out="$(git -C "$TARGET_ABS" status --porcelain 2>/dev/null)"; then
      echo "remove-path.sh: cannot inspect repo state — refusing" >&2
      exit 2
    fi
    [[ -n "$dirty_out" ]] && TRACKED_DIRTY="$(printf '%s\n' "$dirty_out" | wc -l | tr -d ' ')"
    if ! stash_out="$(git -C "$TARGET_ABS" stash list 2>/dev/null)"; then
      echo "remove-path.sh: cannot inspect stash state — refusing" >&2
      exit 2
    fi
    [[ -n "$stash_out" ]] && STASH_COUNT="$(printf '%s\n' "$stash_out" | wc -l | tr -d ' ')"

    while IFS= read -r ignored; do
      [[ -z "$ignored" ]] && continue
      if clean_path_matches_secret_class "$ignored"; then
        SECRETS_COUNT=$((SECRETS_COUNT + 1))
      fi
    done < <(git -C "$TARGET_ABS" ls-files --others --ignored --exclude-standard 2>/dev/null | tr -d '\r')
  fi

  # Count beyond the main entry: any linked worktree must be removed first.
  # Fail closed like the status/stash checks above: an uninspectable worktree
  # list (corrupt worktree state) must block, not read as 0 and let rm -rf
  # strand the linked worktrees.
  if ! wt_out="$(git -C "$TARGET_ABS" worktree list --porcelain 2>/dev/null)"; then
    echo "remove-path.sh: cannot inspect worktree state — refusing" >&2
    exit 2
  fi
  WORKTREE_COUNT="$(printf '%s\n' "$wt_out" | grep -c '^worktree ' || true)"

  # refs/tags is scanned alongside refs/heads: a local-only tag (never pushed)
  # has no upstream, so the [[ -z "$upstream" ]] branch below counts it. Offline
  # local state cannot prove a tag was pushed, so any local tag fails closed as
  # unpushed — --allow-unpushed is the escape hatch.
  while IFS=' ' read -r ref upstream; do
    [[ -z "$ref" ]] && continue
    if [[ -z "$upstream" ]]; then
      UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
      continue
    fi
    # Fail closed: an unresolvable upstream (pruned remote branch, stale
    # tracking config) counts as unpushed rather than silently as 0-ahead.
    if ! ahead="$(git -C "$TARGET_ABS" rev-list --count "$upstream..$ref" 2>/dev/null | tr -d ' ')" || [[ -z "$ahead" ]]; then
      UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
      continue
    fi
    [[ "$ahead" -gt 0 ]] && UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
  done < <({
    git -C "$TARGET_ABS" for-each-ref refs/heads --format='%(refname:short) %(upstream:short)' 2>/dev/null
    git -C "$TARGET_ABS" for-each-ref refs/tags --format='%(refname:short) %(upstream:short)' 2>/dev/null
  } | tr -d '\r')

  if [[ "$KIND" == repo ]] &&
    [[ -z "$(git -C "$TARGET_ABS" branch --show-current 2>/dev/null | tr -d '\r')" ]] &&
    git -C "$TARGET_ABS" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    UNPUSHED_REFS=$((UNPUSHED_REFS + 1)) # detached HEAD — commits may be unreachable elsewhere
  fi
else
  # Plain leftover directory: none of the repo guards above run, but the PR
  # supports deleting such dirs, so a leftover secret-class file would otherwise
  # be discarded silently. Walk descendants and gate on the same SECRETS class,
  # passing target-relative paths so the dir-prefix patterns (.aws/, .vscode/…)
  # match as well as the basename globs.
  while IFS= read -r -d '' f; do
    if clean_path_matches_secret_class "${f#"$TARGET_ABS"/}"; then
      SECRETS_COUNT=$((SECRETS_COUNT + 1))
    fi
  done < <(find "$TARGET_ABS" -mindepth 1 -print0 2>/dev/null)
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

# Defense in depth beyond the device check above: stop rm from crossing into a
# descendant mount point during the recursive delete. --one-file-system is GNU
# coreutils (Linux, MSYS); omitted on BSD/macOS rm, which lacks the long option
# (the device and path checks still bound the target itself).
rm_flags=(-rf)
if rm --version 2>/dev/null | grep -qi coreutils; then
  rm_flags+=(--one-file-system)
fi
rm "${rm_flags[@]}" "$TARGET_ABS"
if [[ -e "$TARGET_ABS" ]]; then
  echo "remove-path.sh: removal incomplete (locked / in use / crosses a mount): $TARGET_ABS" >&2
  exit 1
fi
printf 'Applied: rm -rf %s\n' "$TARGET_ABS"
exit 0

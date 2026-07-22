---
name: clean
description: "Repo hygiene action-router: scan (inventory), caches, build, git (prune/branch audit), tree (destructive fresh-pull reset), tree-batch (multi-repo tree reset with skip-list + dirty guard), all, and fleet batch forms of the selective tiers (caches-batch / build-batch / git-batch / all-batch over many repos behind one gate). Bare invocation detects intent from conversation or shows a menu. Dry-run-first; destructive actions require explicit confirmation. Use when: clean, disk space, remove caches, build artifacts, fresh pull, fresh clone state, reset to origin, reset all my repos, clean caches across all repos, clear build artifacts across all my repos, prune git across the fleet, stale branches, repo hygiene. Skip: removing git worktree directories (a worktree-management tool handles those)."
user-invocable: true
argument-hint: "[scan|caches|build|git|tree|tree-batch|all|caches-batch|build-batch|git-batch|all-batch|aliases…] (bare → menu or auto-detect)"
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/*)
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        # Shell form (no `args`) on purpose: exec form resolves `command` via PATH,
        # which on Windows finds the WSL relay (System32\bash.exe) and the guard
        # never launches — a silent fail-open. Shell form with `shell: bash` makes
        # Claude Code itself resolve Git Bash on every platform.
        - type: command
          command: "bash \"${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/destructive-guard.sh\""
          shell: bash
shell: bash
---

## Pre-computed context

Uncommitted changes: !`git status --porcelain 2>/dev/null | head -5 || echo ""`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Return the repo toward a known-good state. **Selective tiers** (`scan`, `caches`, `build`, `git`, `all`) remove *artifacts* while preserving secrets, runtime deps, and skill data. **`tree`** is the destructive tier — `reset --hard` + `clean -fdx`, but **safe-by-default**: it preserves the same secrets / runtime-deps / skill-data classes unless you opt in via `--include-deps` / `--include-secrets`.

Bare invocation never mutates silently: resolve intent → dry-run → user confirmation → `--apply`. Full menu, aliases, and confirmation matrix: [context/action-router.md](context/action-router.md).

## Arguments

`$ARGUMENTS` — cleanup action or alias. Resolve first:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/resolve-clean-action.sh $ARGUMENTS
```

### Bare invocation (empty args)

1. Infer from conversation (fresh pull → `tree`, disk space → `scan`, … — see action-router).
2. If still unclear, present the action table from [context/action-router.md](context/action-router.md) and `AskUserQuestion`.
3. Safest fallback: `scan`.

### Action table

| Action | Say it as… | Risk | Pre-flight? | In `all`? |
|--------|------------|------|-------------|-----------|
| `scan` | Show what's reclaimable | Safe | No | — |
| `caches` | Clear tool and linter caches | Low | Yes | — |
| `build` | Clear build output and logs | Low | Yes (includes caches) | — |
| `git` | Prune stale git metadata; audit branches | Low | No | Yes |
| `tree` | Reset working tree like a fresh pull | **Destructive** | No (always dry-run first) | **Never** |
| `tree-batch` | Reset many repos like a fresh pull (skip-list + dirty guard) | **Destructive** | No (always dry-run first) | **Never** |
| `all` | Sweep caches + build + git hygiene | Medium | Yes | — |

Tiers cumulative: `build` includes `caches`. `all` = `build` + `git`. **Neither `tree` nor `tree-batch` is ever composed into `all`.**

**Fleet (batch) forms.** Each selective tier has a multi-repo form — `caches-batch`, `build-batch`, `git-batch`, `all-batch` — that runs it across a repo set behind ONE gate (§8). `tree-batch` is the destructive tier's separate batch form (§6.5).

Aliases (`fresh`, `inventory`, `artifacts`, `caches-fleet`, …): [context/action-router.md](context/action-router.md).

## What clean NEVER touches by default

Protected-path enforcement gates `scan`, `caches`, `build`, `git`, AND `tree` (`tree` honors the same classes by default). Full list: [reference/cleanup-config.md](reference/cleanup-config.md).

- **Secrets / config** — `.env*`, `*.local.json` / `.jsonc` / `.md`, IDE user config — `tree` removes only with `--include-secrets` (UNRECOVERABLE).
- **Runtime dependencies** — `node_modules/`, `.venv/`, `vendor/` — `tree` removes only with `--include-deps` (rebuildable).
- **Skill-owned `data/`** — user-generated synthesis — always preserved; no flag removes it.

`tree` requires explicit confirmation and is never auto-invoked. Any file tracked by git is reset via `git reset --hard`, not selective deletion — and any tracked file deleted by reparse-point traversal (junction/symlink into a tracked dir) is auto-restored.

**Session-scoped destructive guard (frontmatter hook).** While this skill is active, a PreToolUse hook (`scripts/destructive-guard.sh`) blocks destructive Bash commands (`rm -rf`, `git clean -f*`, `git reset --hard`, `git checkout --`, recursive `Remove-Item`). After the dry-run → user-confirmation gate passes, re-issue the confirmed command with the acknowledgement prefix `CLEAN_GUARD_ACK=1 <command>` — never add the prefix without the user's explicit confirmation in this session. Kill switch: the `clean_destructive_guard_enabled` userConfig option set to `false` (`/plugin configure repo-hygiene`).

## Cleanup configuration

Per-tier targets: [reference/cleanup-config.md](reference/cleanup-config.md). Script binding: `scripts/lib/cleanup-paths.sh`.

## Workflow

### 0. Resolve action

Run `resolve-clean-action.sh`. If `Action: menu`, show table + ask. Otherwise dispatch to the matching § below. **Never `--apply` on first invocation.**

### 0. Resolve repo root

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

### 1. Scan (`scan`)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/scan.sh` — read-only inventory. Stop if action is `scan`.

### 1.5. Pre-flight (caches / build / all only)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/preflight.sh` — see [context/preflight.md](context/preflight.md). Interactive: `AskUserQuestion` before `--apply` when non-empty. Autonomous: abort.

#### Dry-run → confirm → apply manifest flow (caches / build)

Both selective mutating tiers pay the filesystem walk **once**. `--dry-run` writes a session-scoped manifest and prints two machine-parseable lines: `Manifest: <path>` and `Summary: planned=N bytes=K` (bytes reclaimable — surface this in the confirmation gate). After the user confirms, apply the **same** manifest with `CLEAN_GUARD_ACK=1 … --apply --manifest <path>` — apply re-stats each entry (staleness guard) and removes it without re-walking, then prints `Summary: removed=N failed=M bytes=K` and exits non-zero if `failed>0`. A killed apply **resumes** by re-running the identical `--apply --manifest <path>` (already-removed entries are idempotent no-ops). Capture `<path>` from the dry-run's `Manifest:` line and thread it through unchanged; the manifest is ephemeral (mktemp default), so pass `--manifest <path>` on the dry-run too if you need a stable location.

### 2. Caches

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-caches.sh` — default `--dry-run`; apply per the manifest flow above (`--apply --manifest <path>`) only after confirmation.

### 3. Build (includes caches)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-build.sh --include-caches` — default `--dry-run`; apply per the manifest flow above only after confirmation. `--include-caches` folds the caches tier into the one build manifest.

### 4. Git

**Write-safe metadata only** — not working-tree reset (that is §6 `tree`).

#### 4.1 Prune and gc

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-prune.sh` — `--dry-run` default; `--apply` after confirmation.

#### 4.2 Branch audit

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-audit.sh` — deletion via `AskUserQuestion` per [context/git-branch-cleanup.md](context/git-branch-cleanup.md).

### 5. All

§1.5 once, then §2–§4. **Does not run §6.**

### 6. Tree (destructive)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-tree-reset.sh` — default `--dry-run`. Detail: [context/git-tree-reset.md](context/git-tree-reset.md). Default-preserve; opt-in `--include-deps` / `--include-secrets`; `--allow-unpushed` when HEAD is ahead of upstream.

**Mandatory gate:** show dry-run output → `AskUserQuestion` → only then `--apply`. Surface the dry-run's `PreserveDeps` / `PreserveSecrets` / `AheadCount` lines in the confirmation so the user knows what survives. An exit 4 (`unpushed-commits`) or non-zero `AheadCount` means HEAD has unpushed commits — confirm loss before adding `--allow-unpushed`. Autonomous sessions: abort. Post-step: after a tree reset that removed dependencies, suggest reinstalling them with the project's own bootstrap/setup and re-validating the environment. For a truly pristine tree, close running dev tooling first (MCP servers, telemetry collectors, build/test watchers) — live processes recreate ignored dirs (`obj/`, `node_modules/`, and the like) the moment they are deleted, and may hold locks that surface as `Unremovable:`.

### 6.5. Tree batch — multi-repo (destructive)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-tree-reset-batch.sh` — default `--dry-run`. Runs §6 `tree` across a set of repos behind one gate, with a separator-agnostic skip list and a dirty-by-default guard. Detail + examples: [context/git-tree-reset-batch.md](context/git-tree-reset-batch.md). Additive over §6 — the batch layer runs no destructive git itself; each per-repo reset delegates to the unchanged `git-tree-reset.sh`, preserving every single-repo gate.

Repo sources: `--repo` (repeatable; a shell glob expands to these) and `--repos-from FILE|-` (ingests `ghq list -p` output). Skip list: `--skip ENTRY` / `--skip-from FILE` (absolute path, `owner/repo`, or bare `repo`; separator-agnostic). Passthrough to the child: `--force-default-branch` / `--include-deps` / `--include-secrets`.

**Mandatory gate (single, batch-wide):** show the `--dry-run` whole-batch plan (per-repo `Outcome`/`Reason`, the `Summary` totals, and any `UnmatchedSkip:` warnings) → `AskUserQuestion` **once** → only then `--apply` **once**. Do not gate per repo. A fresh-clone fleet is typically all on the default branch, so expect an all-blocked dry-run unless `--force-default-branch` — surface that in the confirmation. `--include-dirty` re-enables the exact data-loss vector (resets repos with uncommitted/untracked changes or unpushed commits); it needs its own explicit confirmation naming the dirty repos, exactly like `--include-secrets`. Autonomous sessions: abort.

### 7. Orphaned path removal (destructive, on explicit request only)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/remove-path.sh <target>` — default `--dry-run`. Removes a whole clone or leftover directory under the ghq root (`--root` overrides) — e.g. a local clone whose upstream repository was deleted. Not composed into any tier and never inferred: run it only when the user explicitly asks to delete that path. Guards resolve paths physically and require the target to share the root's filesystem device (symlink/junction/cross-mount ancestors cannot escape containment), and refuse the containment root, symlink targets, linked worktrees (that lifecycle belongs to `git worktree remove`), any plain directory still holding nested git repos (normal, bare, or worktree), any target holding ignored skill-owned `data/` (irreplaceable — no override; move it out first), and any repo with uncommitted changes, stashes, registered worktrees, ignored secret-class files (`--include-secrets` to discard), or unpushed refs (`--allow-unpushed` to discard).

**Mandatory gate:** show dry-run output → `AskUserQuestion` → only then `--apply`. Surface `Kind` / `UnpushedRefs` / `SecretsCount` / `SkillData` in the confirmation. Autonomous sessions: abort.

**Documented boundaries.** Containment is path- and device-based (physical resolution plus a same-device check). A *same-device* `mount --bind` under the root shares the root's filesystem device, so no path-based check can detect it; closing that would require a Linux-only mount-table (`/proc/self/mountinfo`) model that would also refuse legitimate under-root mounts, so it stays out of scope for this local, dry-run-default, explicit-`--apply` tool. The unpushed-ref guard covers `refs/heads` and `refs/tags`; other locally-created namespaces (e.g. `refs/notes`) are not scanned, and auto-generated ones (`refs/prefetch/*` from git-maintenance, `refs/replace/*`) are intentionally not treated as unpushed — `--allow-unpushed` is the escape hatch for any local ref. The secret scan gates only ignored (unrecoverable) files; tracked files are git's domain (recoverable via reset/remote, and separately blocked when dirty or unpushed).

### 8. Batch — multi-repo selective tiers (`caches-batch` / `build-batch` / `git-batch` / `all-batch`)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh --tier <caches|build|git|all>` — default `--dry-run`. Runs the §2–§5 selective tiers across a set of repos behind one gate, the selective-tier sibling of §6.5 `tree-batch`. Detail + examples: [context/clean-batch.md](context/clean-batch.md). Additive over the single-repo tiers — the batch layer runs no removal itself; each per-repo action delegates to the unchanged child (`clean-caches.sh` / `clean-build.sh` / `git-prune.sh`), preserving every child gate. **`tree` is not batched here** (use §6.5); **branch audit/deletion is not batched** (interactive per-branch deletion can't sit behind one gate) — batch `git` is prune/gc/remote-prune only, once per unique shared object store.

Repo sources: `--repo` (repeatable; a shell glob expands to these) and `--repos-from FILE|-` (ingests `ghq list -p`; backslash paths normalized). Skip list: `--skip ENTRY` / `--skip-from FILE` (same separator-agnostic matcher as `tree-batch`).

**Mandatory gate (single, batch-wide):** run `--dry-run` once → it writes a **batch plan** and prints `BatchPlan: <path>`, per-repo `Outcome`/`Reason`, any `UnmatchedSkip:`, and an aggregate `Summary: repos=N planned=P bytes=K` (surface the reclaimable `bytes`). `AskUserQuestion` **once** → then `CLEAN_GUARD_ACK=1 … --apply --batch-plan <path>` **once**. The plan IS the gated set: apply targets exactly those repos (`--apply` errors without `--batch-plan`), so a repo that vanished after the dry-run applies idempotently and one that appeared is never touched. Apply prints `Summary: removed=N failed=M bytes=K` and exits non-zero on any failure. Autonomous sessions: abort.

## Integration

| Surface | Relationship |
|-------|-------------|
| A worktree-management tool | Removes git worktree directories — not in-place reset |
| The project's build / verify workflow | Rebuild after `build` or `tree` |
| The project's bootstrap/setup | Restore dependencies after `tree` |
| The project's environment-validation tooling | Full env validation after `tree` or `all` |

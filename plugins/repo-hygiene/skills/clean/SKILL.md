---
name: clean
description: "Repo hygiene action-router: scan (inventory), caches, build, git (prune/branch audit), tree (destructive fresh-pull reset), all. Bare invocation detects intent from conversation or shows a menu. Dry-run-first; destructive actions require explicit confirmation. Use when: clean, disk space, remove caches, build artifacts, fresh pull, fresh clone state, reset to origin, stale branches, repo hygiene. Skip: removing git worktree directories (a worktree-management tool handles those)."
user-invocable: true
argument-hint: "[scan|caches|build|git|tree|all|aliases…] (bare → menu or auto-detect)"
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/*)
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "\"${CLAUDE_PLUGIN_ROOT}\"/skills/clean/scripts/destructive-guard.sh"
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
| `all` | Sweep caches + build + git hygiene | Medium | Yes | — |

Tiers cumulative: `build` includes `caches`. `all` = `build` + `git`. **`tree` is never composed into `all`.**

Aliases (`fresh`, `inventory`, `artifacts`, …): [context/action-router.md](context/action-router.md).

## What clean NEVER touches by default

Protected-path enforcement gates `scan`, `caches`, `build`, `git`, AND `tree` (`tree` honors the same classes by default). Full list: [reference/cleanup-config.md](reference/cleanup-config.md).

- **Secrets / config** — `.env*`, `*.local.json` / `.jsonc` / `.md`, IDE user config — `tree` removes only with `--include-secrets` (UNRECOVERABLE).
- **Runtime dependencies** — `node_modules/`, `.venv/`, `vendor/` — `tree` removes only with `--include-deps` (rebuildable).
- **Skill-owned `data/`** — user-generated synthesis — always preserved; no flag removes it.

`tree` requires explicit confirmation and is never auto-invoked. Any file tracked by git is reset via `git reset --hard`, not selective deletion — and any tracked file deleted by reparse-point traversal (junction/symlink into a tracked dir) is auto-restored.

**Session-scoped destructive guard (frontmatter hook).** While this skill is active, a PreToolUse hook (`scripts/destructive-guard.sh`) blocks destructive Bash commands (`rm -rf`, `git clean -f*`, `git reset --hard`, `git checkout --`, recursive `Remove-Item`). After the dry-run → user-confirmation gate passes, re-issue the confirmed command with the acknowledgement prefix `CLEAN_GUARD_ACK=1 <command>` — never add the prefix without the user's explicit confirmation in this session. Kill switch: `HOOK_CLEAN_DESTRUCTIVE_GUARD_ENABLED=false`.

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

### 2. Caches

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-caches.sh` — default `--dry-run`; `--apply` only after confirmation.

### 3. Build (includes caches)

`bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-build.sh --include-caches` — default `--dry-run`; `--apply` after confirmation.

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

## Integration

| Surface | Relationship |
|-------|-------------|
| A worktree-management tool | Removes git worktree directories — not in-place reset |
| The project's build / verify workflow | Rebuild after `build` or `tree` |
| The project's bootstrap/setup | Restore dependencies after `tree` |
| The project's environment-validation tooling | Full env validation after `tree` or `all` |

---
name: worktree
description: "Manage git worktree lifecycle for parallel-session isolation: create (guided naming via EnterWorktree), status (PR + staleness inventory), cleanup (file-lock-aware removal), audit (infrastructure health). Use when: 'create worktree', 'worktree status', 'clean up worktrees', 'orphaned worktrees', or proactively when on main before writing code — not for PR lifecycle (use /pull-request)."
user-invocable: true
disable-model-invocation: false
argument-hint: "<action> [args] (e.g., /worktree create feat/my-feature, /worktree status, /worktree cleanup, /worktree audit)"
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Worktree inventory: !`git worktree list 2>/dev/null | head -30 || echo "not a git repo"`
Git dir: !`git rev-parse --git-dir 2>/dev/null || echo "none"`
Git common dir (differs from git dir when in a linked worktree): !`git rev-parse --git-common-dir 2>/dev/null || echo "none"`

## Purpose

Orchestrate git worktree lifecycle from creation through cleanup. **Front-half** of the development workflow — gets you into a worktree and keeps them healthy. `/pull-request` is the **back-half** — handles prep, PR creation, monitoring, merge.

**Why this exists:** worktrees are the isolation mechanism for parallel code changes — multiple Claude Code sessions on different tasks without stepping on each other. In repos where branch protection blocks direct commits to main, every feature, fix, or refactor starts with a worktree or branch; this skill makes that seamless.

## Adapting to your environment (graceful degrade)

This skill is self-contained — every action runs on plain `git`, plus `gh` for PR cross-referencing where available. Where it mentions an adjacent capability (an issue tracker, a build/lint verifier, a session-start setup hook), treat it as optional: use it when your environment provides it, proceed without it otherwise. Project-specific conventions — branch naming, worktree layout, which gitignored files a fresh worktree needs — come from the consuming project's own `CLAUDE.md`, rules, and hooks; read them before creating or removing anything.

## Arguments

`$ARGUMENTS` — action selector. Parse first token as action, remainder as arguments.

| Action | Entry point | Use case |
|--------|-------------|----------|
| *(empty)* | Smart default | Detect current state, suggest appropriate action |
| `create [name]` | Create worktree | Validate name, explain setup, call EnterWorktree |
| `status` | Inventory | List all worktrees with PR status and staleness |
| `cleanup [--dry-run]` | Remove stale | Prune orphans, detect merged PRs, remove with confirmation |
| `audit` | Health check | Run status + verify configuration health |

---

## Action: Smart Default (empty args)

Detect current state and guide user to the right action.

1. **Check git repo**: `git rev-parse --is-inside-work-tree`. If not in a repo → "Not in a git repository."

2. **Detect current branch**: `git rev-parse --abbrev-ref HEAD`

3. **Check if in a worktree**: `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir` in any linked worktree. Common layouts: a `.worktrees/` directory sibling to the repo's `.claude/`, Claude Code's default `.claude/worktrees/`, or a bare-clone hub (`git rev-parse --git-common-dir` ends in `.bare` and worktrees are siblings of `.bare/`).

4. **Branch-based guidance**:

   - **On the default branch** → "You're on `<default-branch>`. Create a branch (`git checkout -b <type>/<description>`) or use `/worktree create` if you need parallel session isolation."
   - **In a worktree** → Show current worktree info: branch name, last commit, associated PR (via `gh pr list --head <branch> --json number,title,state`). If a PR exists, suggest the next `/pull-request` phase.
   - **On a feature branch (not worktree)** → Show branch info and any associated PR.

5. **Check for stale/prunable worktrees**: Run a `git worktree list --porcelain` scan. If any worktrees are prunable or branches have merged PRs → suggest `/worktree cleanup`.

6. **Otherwise** → Show brief status summary (worktree count, any needing attention).

---

## Action: `create [name]`

Create a new worktree with guided naming and setup verification. Full procedure — pre-flight guards (already-in-worktree, mid-session transition), name validation (EnterWorktree schema constraints), base-ref notes, the explain-before-create block, directory-rename caveats, and post-create setup checks: [context/create.md](context/create.md).

**Safety invariant create MUST honor:** Call `EnterWorktree(name: "<validated-name>")` as the **final action** — working directory changes and session state transitions on that call, so nothing may execute after it.

---

## Action: `status`

Inventory all worktrees with PR association and staleness detection. Collect Tier-0 facts with plain git + gh (`git worktree list --porcelain` parse, one batched `gh pr list`, last-commit dates), then apply the 6-status classification table (`active` / `stale` / `in-review` / `merged` / `prunable` / `locked`), staleness threshold (14-day default, `WORKTREE_STALE_DAYS` override), and presentation schema per [context/status.md](context/status.md). `audit` Step 1 invokes this logic internally.

---

## Action: `cleanup [--dry-run]`

Remove stale worktrees, orphaned metadata, and branches from merged PRs. Full 5-step procedure — prune orphaned metadata → identify candidates (4 detection reasons: orphaned dir / prunable / PR-merged / stale) → present → execute (4a release file locks, 4b remove, 4c emit branch deletion for the user) → verify physical deletion: [context/cleanup.md](context/cleanup.md). `--dry-run` reports candidates and takes no action.

**Safety invariants cleanup MUST honor** (full detail in context/cleanup.md):

- **Release OS file locks BEFORE `git worktree remove --force`** (Step 4a) — on Windows `--force` unregisters the worktree from git but leaves a husk on disk if a process holds a file handle. Stop build servers (`dotnet build-server shutdown`, Gradle `--stop`, or your stack's equivalent) and worktree-rooted daemons/MCP servers first; stop ONLY those (never another live worktree's processes).
- **Never swallow removal stderr** (`2>/dev/null`) — a failed removal must surface so Step 5 reports husks honestly rather than counting one as removed.
- **Emit `git branch -D` + self-worktree removal for the USER to run, never inline** (Step 4c) — deleting a branch is destructive (and the consuming project's hooks may block it mid-session); a worktree can't delete itself (the running Claude Code session holds its handle). `-D` (not `-d`) is needed because squash-merge changes the SHA.

---

## Action: `audit`

Periodic health check for worktree infrastructure — suitable as a recurring work item in your tracker. **Step 1:** run the `status` action internally, flagging any worktrees with issues (stale, merged-not-cleaned, prunable). The Step 2 configuration-health checklist (`delete_branch_on_merge`, gitignored-file propagation) and the Step 3 findings presentation: [context/audit.md](context/audit.md).

---

## What this skill does NOT do

- **Does not push, create, merge, or close PRs** — `/pull-request` owns the back-half (prep, create, monitor, merge).
- **Does not commit or stage code** — staging and committing stay user-controlled; `/commit` owns the commit mechanic.
- **Does not run CI, build, test, or lint** — use your project's build/test/lint tooling or skills.
- **Does not manage remote branches** — GitHub's `delete_branch_on_merge` handles remote cleanup on merge (when enabled); local `git branch -D` is emitted for the user, never run inline.
- **Does not enforce branch naming** — the consuming project's hooks and CI are the gates. This skill only surfaces the project's convention (read it from the project's `CLAUDE.md` / rules; default suggestion: `<type>/<kebab-description>` with a Conventional Commits type prefix).

## Integration Points

This skill complements other workflow components — it does not duplicate their logic.

| Component | Relationship |
|-----------|-------------|
| `/pull-request merge` (Phase 4) | Handles post-merge cleanup as part of PR lifecycle. `/worktree cleanup` is the standalone version for ad-hoc or batch cleanup |
| `/pull-request create` (Phase 2.1) | Detects default-branch checkout and suggests `/worktree create` |
| Project session-start hooks (if any) | May warn on main or auto-configure fresh worktrees; this skill verifies setup ran per context/create.md's post-create checks |
| Recurring maintenance tracker items | Can invoke `/worktree audit` periodically |

## Graceful Degradation

- **`gh` CLI unavailable or fails**: `status` and `cleanup` work with git-only data. PR cross-reference and the `delete_branch_on_merge` check are skipped with note: "GitHub API unavailable — PR status unknown."
- **Not in a git repo**: All actions exit immediately with "Not in a git repository."
- **`WORKTREE_STALE_DAYS` invalid**: Falls back to 14-day default silently.
- **No worktrees exist**: `status` reports "No linked worktrees found." `cleanup` reports "Nothing to clean up."

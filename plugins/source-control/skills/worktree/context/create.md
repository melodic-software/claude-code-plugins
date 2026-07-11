# Worktree `create` — pre-flight, naming, base-ref, setup verification

Full detail for the `/worktree create [name]` action. SKILL.md carries the headline plus the `EnterWorktree`-as-final-action safety invariant; this file carries the pre-flight guards, name validation, base-ref selection, the explain-before-create block, the directory-rename caveats, and the post-create setup checks.

Create a new worktree with guided naming and setup verification.

## Pre-flight checks

1. **Already in a worktree?** Check whether CWD is a linked worktree: `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir` (covers every layout — `.worktrees/`, `.claude/worktrees/`, bare-clone hub). If yes → "Already in a worktree (`<current-branch>`). Use `ExitWorktree` to leave this one first, then `/worktree create` again."

2. **Mid-session transition?** If the session previously used `ExitWorktree` (CWD is now the main repo root, not a worktree), this is a worktree transition — fully supported. Session context persists across the transition. Proceed normally.

3. **Name provided?** If `$ARGUMENTS` has a name after `create`, use it. Otherwise, prompt the user for a name following the project's branch naming convention (read it from the project's `CLAUDE.md` / rules; common default: `<type>/<kebab-description>` with a Conventional Commits type prefix — `feat/`, `fix/`, `chore/`, etc.). Passing a convention-conforming name matters because the worktree's branch is derived from it.

## Name validation

The name passed to `EnterWorktree` has these constraints (from the tool schema):

- Each `/`-separated segment may contain only **letters, digits, dots, underscores, and dashes**
- Max **64 characters** total
- `/` is a valid segment separator (enables `feat/my-feature` format)

Validate the name against these rules. If invalid, explain what's wrong and ask for correction.

## Base branch

By default, Claude Code's `worktree.baseRef` setting governs the base: `fresh` (default) branches new worktrees from `origin/<default-branch>`; `head` branches from the local `HEAD` so unpushed commits carry in. Consuming projects may override worktree creation with their own `WorktreeCreate` hook (custom path layout, branch derivation) — when such a hook exists, its behavior wins; read the project's docs. To start from a different base explicitly, create manually: `git worktree add -b <type>/<desc> <path> <base>`.

## Explain what will happen

Before calling EnterWorktree, tell the user:

```text
Creating worktree:
  Directory: <worktree-path>/          (Claude Code default, or your project's
                                        WorktreeCreate-hook layout)
  Branch: <name>                       (derived from the name you pass)
  Setup: your project's session-start hooks (if any) run on next SessionStart;
         mid-session EnterWorktree may need a manual setup re-run

Optional renames after creation:
  git branch -m <old> <type>/<description>          # sharpen the branch name
  git worktree move <old-path> <new-path>           # rename the directory
```

**Directory renaming via `git worktree move`:** rename at any time with `git worktree move <old-path> <new-path>` — updates Git's internal references automatically. Run it from outside the worktree being moved (e.g., from main). Caveats:

- **Session history**: Claude Code's `~/.claude/projects/` directory is keyed by worktree filesystem path. Moving the directory orphans the old project key — `--resume`/`--continue` from a new session won't find the old transcript. Auto-memory and project config are shared at repo level and are NOT affected.
- **Windows**: works on Git Bash/NTFS with no known issues. Use forward slashes or quote paths with spaces.
- **Cannot move**: the main worktree, or worktrees containing submodules.
- **Locked worktrees**: require `--force --force` (twice).

## Create the worktree

Call `EnterWorktree(name: "<validated-name>")` as the **final action**. Nothing should execute after this call because the working directory changes and session state transitions.

If the project has session-start setup hooks, they run on the next SessionStart; for mid-session `EnterWorktree`, SessionStart may not fire — run the project's setup steps manually if the checks below fail.

**Universal checks** (apply in every worktree regardless of ecosystem):

| Check | Command | Fix hint |
|-------|---------|----------|
| Local settings/secrets present | e.g. `test -f .claude/settings.local.json` (when the project uses one) | Copy from the main repo checkout, or rely on the project's `.worktreeinclude` (Claude Code copies matching gitignored files at creation) |
| Git hooks installed | Depends on the project's hook manager (e.g. `lefthook list`, `husky` install state) | Run the project's hook-install command |

**Ecosystem checks** (each gated on a trigger glob — skip silently if no matching files exist in the worktree root):

| Ecosystem | Trigger glob | Check | Command |
|-----------|--------------|-------|---------|
| .NET | `*.sln`, `*.slnx` | dependencies restored | `dotnet restore` |
| Node | `package.json` | dependencies installed | `npm install` (or the project's package manager) |
| Python | `pyproject.toml` | environment synced | `uv sync` / `pip install -e .` |

Gitignored files (secrets, `.venv/`, `node_modules/`, build output) do NOT propagate to a fresh worktree — that is what these checks catch.

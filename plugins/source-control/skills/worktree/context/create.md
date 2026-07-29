# Worktree `create` — pre-flight, naming, base-ref, setup verification

Full detail for the `/worktree create [name]` action. SKILL.md carries the headline plus the shared-helper safety invariant; this file carries the pre-flight guards, name validation, base-ref selection, the explain-before-create block, the directory-rename caveats, and the post-create setup checks.

`create` does **not** call `EnterWorktree(name:)` (which lands in the in-repo `.claude/worktrees/`, triggering Claude Code's CLAUDE.md/rules double-load bug — #400, upstream anthropics/claude-code #29599 / #23565). It routes through the shared helper `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh`, which places the worktree at an **external root** (`<root>/<owner>-<repo>-<slug>`), copies `.worktreeinclude` files, and prints the path; the skill then calls `EnterWorktree(path:)` on that path.

Create a new worktree with guided naming and setup verification.

## Pre-flight checks

1. **Already in a worktree?** Check whether CWD is a linked worktree: `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir` (covers every layout — `.worktrees/`, `.claude/worktrees/`, bare-clone hub). If yes → "Already in a worktree (`<current-branch>`). Use `ExitWorktree` to leave this one first, then `/worktree create` again."

2. **Mid-session transition?** If the session previously used `ExitWorktree` (CWD is now the main repo root, not a worktree), this is a worktree transition — fully supported. Session context persists across the transition. Proceed normally.

3. **Name provided?** If `$ARGUMENTS` has a name after `create`, use it. Otherwise, prompt the user for a name following the project's branch naming convention (read it from the project's `CLAUDE.md` / rules; common default: `<type>/<kebab-description>` with a Conventional Commits type prefix — `feat/`, `fix/`, `chore/`, etc.). Passing a convention-conforming name matters because the worktree's branch is derived from it.

## Name validation

The name (branch and, via the helper's slug, directory) has these constraints (the `EnterWorktree` schema plus the helper's slug rules):

- Each `/`-separated segment may contain only **letters, digits, dots, underscores, and dashes**
- Max **64 characters** total
- `/` is a valid segment separator (enables `feat/my-feature` format)
- The name must also be a **legal git branch name** (`git check-ref-format --branch`). The character rule above does not imply this — `feat/foo..bar`, `foo.lock`, `.foo`, `HEAD`, and `-lead` all satisfy it yet git rejects them as refs. The helper checks this after resolving the repository, so exits 3 and 4 can precede an invalid-name exit 2.

Validate the name against these rules. If invalid, explain what's wrong and ask for correction. The helper re-validates defensively and **refuses** a name that violates them (exit 2) rather than let `git worktree add` fail opaquely. The branch keeps the name verbatim; the helper derives the **directory slug** from it (each `/` → `-`).

## Base branch

The helper's `--base-ref` selects the base: `fresh` (default) branches from the remote default branch; `head` branches from the repo's current `HEAD` so unpushed commits carry in.

For `fresh`, the helper resolves the effective default **remote** first — the current branch's configured remote, else `origin`, else the sole remote — then that remote's default branch symbolically via its `HEAD` symref. A repo cloned with `git clone -o upstream` therefore bases on `upstream`'s default branch rather than degrading to local `HEAD`. When no remote resolves, or the resolved remote's `HEAD` is not cached locally, it falls back to local `HEAD` with a loud warning naming the cause. Note this is deliberately more general than [Claude Code's native `fresh`](https://code.claude.com/docs/en/worktrees#choose-the-base-branch) in remote resolution, which probes `origin/HEAD` only — but not a strict superset of it: the helper reads the cached remote-tracking ref, where native `fresh` also refreshes it by fetching. A `<remote>/HEAD` that is stale locally yields a stale base here.

**The caller owns this choice** — `worktree.baseRef` is a Claude Code **settings.json** key (`{"worktree": {"baseRef": "head"}}`, governing native `EnterWorktree`/`--worktree`), **not** a git config key, so the helper cannot read it. Since this skill bypasses native creation, it must honor the setting itself: read the effective `worktree.baseRef` using Claude Code's settings precedence — local `.claude/settings.local.json` over project `.claude/settings.json` over user `~/.claude/settings.json`; if it is `head`, pass `--base-ref head` to the helper; otherwise omit it (the helper defaults to `fresh`). Skipping this read — or reading only project/user and missing a local override — silently forces `fresh` for a user who configured `head`.

To start from a different, specific branch, create manually instead: `git worktree add -b <type>/<desc> <path> <base>`, then `EnterWorktree(path: <path>)`.

## Explain what will happen

Before creating, tell the user:

```text
Creating worktree (shared helper — external root, avoids the #400 double-load bug):
  Directory: <root>/<owner>-<repo>-<slug>   (root = the worktree_root config key)
  Branch: <name>                            (kept verbatim; slug derived for the dir)
  Local files: .worktreeinclude matches copied in (gitignored ones only)
  Entering: EnterWorktree(path:) switches the session in. Because the path is
            OUTSIDE .claude/worktrees/, Claude Code asks you to APPROVE the move
            (not suppressible except in bypassPermissions mode) — approve it.
  Setup: your project's session-start hooks (if any) run on next SessionStart;
         a mid-session entry may need a manual setup re-run

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

Two steps — the helper creates and places the worktree; `EnterWorktree(path:)` enters it.

1. **Run the shared helper** (it computes the external path, runs `git worktree add`, and copies `.worktreeinclude` files). Add `--base-ref head` only when the effective Claude `worktree.baseRef` setting is `head` (see [Base branch](#base-branch)); otherwise omit it.

   `${user_config.worktree_root}` substitution into skill content is **raw text substitution, not shell-escaped** (Claude Code docs, [plugins-reference § User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration)) — a configured value containing a single quote (e.g. `~/worktrees/O'Connor`), `$`, or a backtick breaks out of any shell literal we write around it, and **no heredoc delimiter is safe either**: a value whose own body contains a line equal to the delimiter ends the heredoc early and the shell parses the remainder as commands. The value must therefore never reach a shell parser at all. Write it with the **`Write` tool** — the content travels as a JSON string parameter, so every byte lands verbatim and no delimiter, quote, or metacharacter can terminate anything — then hand the file to `--root-file`. Never inline the substitution in a `--root` shell literal or a heredoc body.

   Three steps:

   ```bash
   root_dir="$(mktemp -d)"; printf '%s\n' "$root_dir"
   ```

   `Write(file_path: "<printed root_dir>/worktree-root", content: "${user_config.worktree_root}")` — the substituted value is the entire `content`, written byte-exact with nothing appended (no trailing newline).

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" \
     --name "<validated-name>" --root-file "<root_dir>/worktree-root"
   status=$?
   rm -rf "<root_dir>"
   exit "$status"
   ```

   Two details in that last block are load-bearing:

   - **`mktemp -d`, not `mktemp`** — `Write` refuses to overwrite a file it has not read, so the directory must exist and the file inside it must not.
   - **`status=$?` before the cleanup, `exit "$status"` after** — `rm` almost always succeeds, so leaving it last would make the whole invocation report 0 and hide a helper refusal (exit 3) behind a green result, which step 2's "on a non-zero exit, STOP" would then never see.

   The helper prints the created worktree path as its **sole stdout line**; capture it. When `worktree_root` is unset, Claude leaves the literal `${user_config.worktree_root}` token — `Write` puts that token in the file verbatim, and the helper's existing unset guard still fires (exit 3), same as before. A value carrying a newline byte anywhere — including a trailing one — is rejected loudly by the helper (exit 2); a path with a newline in it is malformed configuration, not a root to silently trim.

2. **On a non-zero exit, STOP — do not create anything else, and never fall back to `EnterWorktree(name:)`** (that would re-create the in-repo `.claude/worktrees/` path and re-trigger #400). The important refusal is **exit 3 (root unconfigured)**: the `worktree_root` key is unset, so the helper declined and printed guidance on stderr. Surface that guidance to the user verbatim — they need to set `worktree_root` (run the worktree setup skill, or `/plugin` configure) — then stop. Other non-zero exits (2 usage, 4 environment — e.g. the branch already exists) surface the helper's stderr and stop likewise.

3. **Enter the worktree** — call `EnterWorktree(path: "<printed-path>")` as the **final action**. Nothing may execute after it: the working directory changes and session state transitions. Because the path is outside `.claude/worktrees/`, Claude Code prompts for approval first (see the explain block); if the user **declines**, the worktree already exists on disk but the session did not enter it — tell them they can retry (approve the prompt) or `cd` into `<printed-path>` in a new session.

If the project has session-start setup hooks, they run on the next SessionStart; for a mid-session entry, SessionStart may not fire — run the project's setup steps manually if the checks below fail.

**Universal checks** (apply in every worktree regardless of ecosystem):

| Check | Command | Fix hint |
|-------|---------|----------|
| Local settings/secrets present | e.g. `test -f .claude/settings.local.json` (when the project uses one) | The helper already copied `.worktreeinclude`-matched gitignored files at creation; for anything not covered by `.worktreeinclude`, copy from the main repo checkout (or add it to `.worktreeinclude`) |
| Git hooks installed | Depends on the project's hook manager (e.g. `lefthook list`, `husky` install state) | Run the project's hook-install command |

**Ecosystem checks** (each gated on a trigger glob — skip silently if no matching files exist in the worktree root):

| Ecosystem | Trigger glob | Check | Command |
|-----------|--------------|-------|---------|
| .NET | `*.sln`, `*.slnx` | dependencies restored | `dotnet restore` |
| Node | `package.json` | dependencies installed | `npm install` (or the project's package manager) |
| Python | `pyproject.toml` | environment synced | `uv sync` / `pip install -e .` |

Gitignored files (secrets, `.venv/`, `node_modules/`, build output) do NOT propagate to a fresh worktree — that is what these checks catch.

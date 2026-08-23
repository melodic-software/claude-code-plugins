---
description: "Batch-run simplification across changed files, or across an entire repository, grouped by ecosystem and dependency order. Use when: 'batch simplify', 'simplify recent changes', 'simplify everything', 'forgot to run simplify', 'catch up on simplify', 'simplify my branch changes', 'simplify the whole repo', 'simplify just this folder', 'simplify everything under <path>', or after a multi-session sprint. Accepts a time window (`24h`, `7d`), `branch` to diff the current branch vs the default branch, or `repo` for a confirmed whole-repository sweep; any scope narrows to one or more trailing paths; optional `docs` flag includes .md files for post-migration or post-refactor doc sweeps. Skip for single-file cleanup. Use /simplify instead."
user-invocable: true
disable-model-invocation: false
argument-hint: "[time-window | branch | repo] [path...] [docs] (e.g., /batch-simplify 72h, /batch-simplify branch docs, /batch-simplify repo plugins/foo. Default: 48h)"
shell: bash
metadata:
  workflow-stage: review
  summary: Batch-run simplification across changed files, or a whole repository, by ecosystem
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Automate running simplification across changed code files, or every code file in the repository, grouped so each pass has tight focus and ecosystem-appropriate context. Replaces the manual process of remembering to run `/simplify` after each task.

## Emit checklist

For any batch run (Phases 1-8), copy `templates/checklist.md` into your project's working-notes location (or track the phases inline if it has none). Tick each phase as completed. Phase 6.5 SKIPPED when no deferred items surface; Phase 5 task tracking SKIPPED for single-group changes.

## Arguments

`$ARGUMENTS`, optional scope for the file scan: `[<scope>] [<path>...] [docs]`. The scope picks a *universe* (three modes below); a path narrows it to a *region*. They are independent, so any scope takes any path.

### Mode 1: Time window (default)

Supported formats: `24h`, `48h`, `72h`, `7d`, `2d`, `1w`. Default: `48h`.

**Normalize before use:** git's `--since` approxidate parser requires `24 hours`, not `24h`. Convert before passing to `git log`:

- `<N>h` → `<N> hours` (e.g., `48h` → `48 hours`)
- `<N>d` → `<N> days` (e.g., `7d` → `7 days`)
- `<N>w` → `<N> weeks` (e.g., `1w` → `1 weeks`)

### Mode 2: Branch diff

Trigger: the remaining argument, lowercased and whitespace-normalized, **equals** one of `branch`, `feature branch`, or `all commits`. Uses `git diff --name-only <default-branch>...HEAD` (three-dot. Diff from the merge base, so files changed only on the default branch since the branch point are NOT swept in) to find files this branch changed. Requires being on a non-default branch.

Match the whole argument, never a substring: an argument that merely *contains* "branch", a path, a filename, a future scope value, is not a branch-mode request, and routing it there silently sweeps the wrong file set.

**Detection heuristic** (after stripping the `docs` flag): read the **first** remaining token as the scope. Matches `^\d+[hdw]$` → time-window mode; equals a branch trigger phrase → branch mode; equals `repo` → repo mode. Empty argument → default `48h`. Every token after the scope is a path.

Decide the scope **before** testing any token as a path, never after. Stripping paths first lets a repository that happens to contain a directory named `repo` or `branch` swallow the scope keyword. `/code-tidying:batch-simplify repo` would resolve `repo` as a path, find no scope left, and silently run the 48-hour default narrowed to that directory instead of the whole-repository sweep that was asked for. If the first token is not a scope, the scope defaults to `48h` and *every* token is a path; a token that resolves to nothing is neither a scope nor a path, so it falls through to asking the user rather than guessing. To sweep a directory genuinely named `repo`, spell it `./repo`.

### Mode 3: Whole repository

Trigger: the remaining argument, lowercased and whitespace-normalized, **equals** `repo`. Sweeps every non-excluded file in the repository rather than a diff, including untracked files that are not ignored, so newly added work is swept too. Explicit entry only: it never auto-escalates from another mode, and it confirms the inventory with the user after Phase 4, once grouping and wave planning have produced the numbers that gate reports, and before any group is dispatched. A trailing path narrows the sweep (see **Narrowing to a path**) without changing any of the above, the confirmation gate still fires, on the narrowed inventory. Repo-scale machinery, grouping, waves, concurrency, resume, delivery, lives in [context/repo-mode.md](context/repo-mode.md), loaded only when this mode fires.

### Narrowing to a path

Any scope accepts one or more trailing paths: `48h plugins/knowledge`, `branch src/`, `repo plugins/code-tidying`. Narrowing is orthogonal to scope because the two answer different questions, the scope decides *which universe* (changed recently, changed on this branch, everything), the path decides *which region of it*. Binding paths to one mode would assert that only that universe may be narrowed, which nothing supports.

Apply the path as a native pathspec on that mode's own discovery command (`-- <path>`), never as a filter over the results: the pathspec is what makes the mode's own semantics hold over the narrowed set. That means merge-base for branch and `--since` for a window.

Resolve each path against the **invocation directory**, then express it **repo-root-relative** before handing it to a root-anchored command. Repo mode runs `git -C <repo-root>`, and `-C` changes directory before the pathspec is applied: a bare `code-tidying` typed from inside `plugins/` resolves locally but would be read at the root as a top-level `code-tidying`, sweeping the wrong set or nothing at all while reporting a clean run.

A token counts as a path only if it **resolves** to an existing file or directory. A token that resolves to nothing is neither a path nor a scope, so it falls through to the ask-the-user rule, which is what keeps a mistyped scope or path an explicit question instead of a silent sweep of nothing.

`repo <lane>` is deliberately **not** accepted; use a path. Rationale in [context/reference.md](context/reference.md) "Why narrowing is a path, not a lane".

### Flag: `docs`

Append `docs` to any mode to include `.md` files in the sweep. By default, `.md` files are excluded because they're prose, not code. The `docs` flag tells the simplifier to review documentation for consistency. Stale references, outdated library names, incorrect API examples, or references to renamed/removed code. Boundary with the sibling `/code-tidying:tidy`: batch-simplify owns factual staleness across the whole doc set in one pass; tidy's `docs-prose` lane owns incremental structural prose work under a scope budget.

**When to use `docs`:**

- After a library migration. Docs may reference old library names or patterns
- After a large refactoring. Docs may reference old file paths, class names, or API shapes
- After renaming or reorganizing modules. Docs may have stale cross-references

**Examples:** `/code-tidying:batch-simplify branch docs`, `/code-tidying:batch-simplify 72h docs`

**Detection:** split `$ARGUMENTS` into whitespace-separated tokens. If any token **equals** `docs` (case-insensitive), set the docs flag and drop that token; rejoin the rest as the remaining argument, which determines the mode.

Strip token-wise, never by substring: a substring strip mutates any argument that happens to contain those four letters, including a path such as `docs/`. Leaving a corrupted remainder for the mode parser to read.

## Workflow

### Phase 1: Discover changed code files

Both modes union committed history with uncommitted changes (staged + unstaged) so nothing is missed. When a path was given, append `-- <path>...` to every git command in this phase, including the working-tree `git diff`, so the narrowing holds over both halves of the union.

**Branch mode** (argument matches the branch/feature-branch/all-commits pattern):

```bash
# Committed on branch (vs merge base) + uncommitted working tree changes
{ git diff --diff-filter=ACDMR --name-only <default-branch>...HEAD; git diff --diff-filter=ACDMR --name-only HEAD; } | sort -u
```

Requires being on a non-default branch. If on the default branch, report the error and exit.

**Time-window mode** (default):

```bash
# Normalize shorthand: 48h → "48 hours", 7d → "7 days", 1w → "1 weeks"
# Committed in window + uncommitted working tree changes
{ git log --since="${NORMALIZED_TIME_WINDOW} ago" --diff-filter=ACDMR --name-only --pretty=format:""; git diff --diff-filter=ACDMR --name-only HEAD; } | sort -u | grep -v '^$'
```

**Repo mode**, the file universe is `git -C "$(git rev-parse --show-toplevel)" ls-files --cached --others --exclude-standard [-- <path>...]`, with any `<path>` converted to repo-root-relative first (the `-C` makes the pathspec root-anchored, so a path typed relative to a subdirectory would otherwise be read against the wrong base), anchored to the repo root so a run started in a subdirectory still sweeps the whole tree. Refuse to start if any file in that universe carries tracked modifications, naming them; scope that check to the swept universe and exclude the working-notes location from both the check and the sweep, a whole-tree refusal would block the checklist this skill writes as its own first step, and would block every resume.

### Phase 2: Filter to code files

Exclude non-code files. Keep only files that benefit from code simplification:

**Include** (code and code-like config):

- `.cs`, `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.py`, `.sh`, `.bash`, `.ps1`, `.psm1`, and any other source-code extensions the project uses
- Build-system config (`.csproj`, `.props`, `.targets`, `package.json`, `pyproject.toml`, and equivalents)
- Project config `.json` / `.jsonc` / `.toml` (e.g. `tsconfig.json`, `biome.json`, `.mcp.json`, not data files)
- Linter/format config (`.editorconfig`, `.gitattributes`, `.gitignore`, `.dockerignore`, `.shellcheckrc`)

**Exclude** (not useful for code simplification):

- `.md` files (documentation. Prose, not code). **Exception:** when the `docs` flag is set, include `.md` files that are NOT in the protected list below. The simplifier reviews docs for stale references, outdated library names, incorrect API examples, or references to renamed/removed code, not for prose quality
- `.lock` files (`uv.lock`, `package-lock.json`. Auto-generated)
- **Agent & enforcement configuration**. `.claude/hooks/**`, `.claude/settings*.json`, `.claude/agents/**`, `.mcp.json`, `.github/workflows/**`, git-hook manager config (`lefthook.yml`, `.husky/**`, `.pre-commit-config.yaml`): never handed to an autonomous simplifier (same safety model as this plugin's tidy skill). If they changed in the window, list them as read-only deferred items instead
- Data files (fixtures, datasets, exported records. Anything that is content rather than logic)
- Skill/agent definition prose (`SKILL.md`, agent markdown), `README.md`, `CLAUDE.md`
- Generated or vendored code, and any directory the consuming repo documents as externally managed or sync-generated, a local edit there is silently overwritten on the next sync, so it is a read-only deferred class rather than a sweep target ([context/repo-mode.md](context/repo-mode.md))

**Append-only / historical-record protection** (applies even when the `docs` flag is set):

- **Filename patterns** (case-insensitive): `CHANGELOG.md`, `CHANGELOG.txt`, `HISTORY.md`, `RELEASES.md`, `NEWS.md`. ADR filenames matching `[0-9]{3,4}-*.md` under any `decisions/` or `adr/` directory (immutable post-acceptance by convention. Supersede, do not edit the body).
- **Body-text declaration**: any file whose first 20 lines contain a case-insensitive match for `append-only`, `append only`, `historical record`, `do not edit historical entries`, or `immutable`. The declaration is the file declaring its own policy. Honor it.
- **Why hard-excluded** (not a default-with-flag-override): a bulk find-replace on a changelog or accepted ADR rewrites history. Readers diffing the file later see what entries say NOW, not what they said when written. If a genuine update is needed, make a manual edit with explicit user authorization. Do not bulk-include via the simplifier.

### Phase 3: Verify existence

Check each file exists on disk. Files may have been deleted or renamed since the commit. Drop any that don't exist.

If no code files remain after filtering, report "No code files changed in {scope}" and exit (where scope is the time window or "branch vs default"). When the scope was a diff, name repo mode in that same report. *"nothing changed in {scope}; `/code-tidying:batch-simplify repo` sweeps the whole repository instead"*, and stop. Offering is not entering: run repo mode only if the user asks for it.

### Phase 4: Group files

Group files by project/ecosystem relatedness. Each group should contain files that share enough context for the simplifier to reason about them together.

**Grouping rules** and **dependency ordering** (root config → agent infra → scripts → shared libs → app code → cross-cutting tests → polyglot services): full priority lists in [context/reference.md](context/reference.md) "Grouping & dependency order (Phase 4)".

### Phase 5: Create tasks

Create one task per group using `TaskCreate`. Each task should include:

- Group number and name
- File list
- Ecosystem (for verification)
- Dependency notes

### Phase 6: Run simplification waves

**Before spawning any agents**, ground the run: if the `discovery` plugin is installed, invoke `/discovery:explore` via the Skill tool on the batch scope and `/discovery:research` via the Skill tool covering idioms relevant to the dominant ecosystems in the wave; otherwise read representative files per group and do a focused inline research pass on the ecosystems' current idioms.

Waves can run in parallel when groups touch non-overlapping files and ecosystems. Launch independent groups in a single message with multiple Agent tool calls; serialize only when groups have direct dependencies.

For each group:

1. **Mark the task in_progress** via `TaskUpdate`

2. **Spawn a simplifier agent** via the `Agent` tool. Use `subagent_type: "pr-review-toolkit:code-simplifier"` when that plugin is installed, else `subagent_type: "general-purpose"`. The prompt MUST include:
   - The complete list of files in the group (absolute paths)
   - The ecosystem and the consuming project's relevant convention files (its `CLAUDE.md` / `.claude/rules` paths), when they exist
   - Instructions to read each file and check for redundancy/inconsistency/dead code/simplification opportunities
   - Instructions to preserve ALL functionality (exit codes, output format, public API, CLI args)
   - The ecosystem-specific verification commands to run after changes (see context/reference.md)
   - An escalation clause: *"If you discover mid-task that the requested change is wrong, conflicts with project conventions, or requires touching files outside your file list, STOP and report back instead of improvising."*
   - **Deferral contract (required):** *"For every simplification you identify but choose NOT to apply, record it in a `## Deferred` section of your final report with this shape per item: `- <path>:<line or range> — <one-line description>. Reason: <why not now>. Scope: <trivial|small|medium|large>. Category: <refactor|dedup|modernize|perf|cleanup>.` Do not silently skip, if you noticed it, list it. This includes: (a) changes out of scope for this wave, (b) changes rejected for safety reasons, (c) changes that would trigger parallel-edit conflicts, (d) cross-file or cross-group refactors. 'Already idiomatic' or 'preserves documented contract' do NOT need to appear. Only candidates you considered actionable but set aside."*

3. **Collect deferred items**, when the agent returns, extract the `## Deferred` section verbatim into a running list keyed by group number. Do not lose or paraphrase these items.

4. **Report results**. Summarize what the agent changed (or didn't) for that group, plus a count of deferred items.

5. **Mark the task completed** via `TaskUpdate`

### Phase 6.5: Capture deferred items as issues

After all groups complete, consolidate the deferred items collected in Phase 6. NON-OPTIONAL, never silently defer: if you notice something and choose not to fix it now, say so and capture it.

1. **Dedupe and group**. Multiple agents may flag the same cross-cutting concern. Merge into single items spanning all identified sites.

2. **Classify by priority:**
   - **High**. Fits the current branch theme. File even if scope is large.
   - **Medium**. Genuine tech debt, would dilute the current PR if bundled.
   - **Low**. Nice-to-have, cross-cutting, low user-visible impact.
   - **Do-not-file**. Genuine judgment calls where the agent's rationale is already a defensible answer. Still present to the user; do NOT drop silently.

3. **Present to the user**, before filing, show the consolidated list grouped by priority with proposed titles. Default to filing High + Medium automatically when running non-interactively; ask for Low and Do-not-file items.

4. **File work items**. One per deferred concern (not per site): invoke `/work-items:track add` via the Skill tool when that plugin is installed, else `gh issue create` (or present the list when no tracker is reachable). Use Conventional Commits-style titles: `refactor(<area>): <what>`. The body should include the rationale the agent recorded, the specific files/lines, and the scope estimate.

5. **Record issue numbers** in the Phase 8 summary report so the user can cross-reference.

### Phase 7: Final cross-ecosystem verification

After all groups complete, run final verification across all affected ecosystems using the consuming project's canonical build/test/lint commands (its `CLAUDE.md` usually names them; generic fallbacks per ecosystem in [context/reference.md](context/reference.md) "Ecosystem verification commands (Phase 7)").

In the diff-scoped modes, time window and branch, simplification is behavior-preserving and this objective cross-ecosystem pass is verification enough: a fresh-context verifier is the rule only where a verdict is subjective, not where the check is a mechanical pass/fail. That exemption is scoped to those modes and does not carry into repo mode, where no human reads the diff before it merges; there a per-group refutation verifier is mandatory ([context/repo-mode.md](context/repo-mode.md)). A change that passes only because it altered behavior is a regression this final verification exists to catch (Gotchas). Files with no mapped test suite are common in any repository: report them as unmapped rather than as passing. In repo mode they fall through to the per-group refutation verifier plus this end-of-run pass, which are then the only checks behind them.

Report the final verification results as a summary table.

### Phase 8: Summary report

Present a final report. Scope + files-scanned + a per-group results table (`# | Group | Files | Changes | Deferred | Verification`) + final cross-ecosystem verdict + filed-issues and judgment-call-deferrals sections. Full template in [context/reference.md](context/reference.md) "Summary report template (Phase 8)".

If zero items were deferred across all groups, state explicitly: *"No items deferred. All identified simplifications were applied or determined to be no-ops."*

## Edge cases

- **No changes in time window**: report and exit cleanly
- **Single file changed**: still run the simplifier (skip grouping, just one group)
- **Agent reports no changes needed**: mark as "reviewed, no changes". Valid outcome. Still inspect the agent's output for a `## Deferred` section; zero applied changes does not mean zero deferrals
- **Agent reports deferrals**: non-optional path. Run Phase 6.5. Never paraphrase or collapse deferred items without presenting them to the user
- **Verification fails after simplification**: report the failure prominently, the agent should have caught this, but the final verification is the safety net
- **Very large groups (>25 files)**: split into sub-groups by subdirectory to keep the simplifier focused
- **Files that span multiple ecosystems**: group by the primary ecosystem (e.g., a `.sh` hook that invokes `ruff` goes in the shell group, not Python)
- **A consumer hook blocks subagent edits**: some projects gate edits behind precondition hooks (e.g., explore/research-first gates). Comply. Satisfy the hook's precondition in the main session, then re-spawn the blocked groups. Do NOT bypass the hook via Bash workarounds and do NOT negotiate with it
- **Commits appear mid-run that this skill didn't make**: parallel sessions or auto-snapshot mechanisms may commit concurrently. `git log --oneline -5` reveals what was captured; treat those commits as authoritative for the changed state and proceed

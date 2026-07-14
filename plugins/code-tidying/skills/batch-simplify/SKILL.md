---
name: batch-simplify
description: "Batch-run simplification across all recently changed files, grouped by ecosystem and dependency order. Use when: 'batch simplify', 'simplify recent changes', 'simplify everything', 'forgot to run simplify', 'catch up on simplify', 'simplify my branch changes', or after a multi-session sprint. Accepts a time window (`24h`, `7d`) or `branch` to diff the current branch vs the default branch; optional `docs` flag includes .md files for post-migration or post-refactor doc sweeps. Skip for single-file cleanup — use /simplify instead."
user-invocable: true
argument-hint: "[time-window | branch] [docs] (e.g., /batch-simplify 72h, /batch-simplify branch docs — default: 48h)"
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Automate running simplification across recently changed code files, grouped so each pass has tight focus and ecosystem-appropriate context. Replaces the manual process of remembering to run `/simplify` after each task.

## Emit checklist

For any batch run (Phases 1-8), copy `templates/checklist.md` into your project's working-notes location (or track the phases inline if it has none). Tick each phase as completed. Phase 6.5 SKIPPED when no deferred items surface; Phase 5 task tracking SKIPPED for single-group changes.

## Arguments

`$ARGUMENTS` — optional scope for the git history scan. Two modes:

### Mode 1: Time window (default)

Supported formats: `24h`, `48h`, `72h`, `7d`, `2d`, `1w`. Default: `48h`.

**Normalize before use:** git's `--since` approxidate parser requires `24 hours`, not `24h`. Convert before passing to `git log`:

- `<N>h` → `<N> hours` (e.g., `48h` → `48 hours`)
- `<N>d` → `<N> days` (e.g., `7d` → `7 days`)
- `<N>w` → `<N> weeks` (e.g., `1w` → `1 weeks`)

### Mode 2: Branch diff

Trigger: argument is `branch`, or contains "branch", "feature branch", or "all commits". Uses `git diff --name-only <default-branch>...HEAD` (three-dot — diff from the merge base, so files changed only on the default branch since the branch point are NOT swept in) to find files this branch changed. Requires being on a non-default branch.

**Detection heuristic** (after stripping the `docs` flag): empty remaining argument → default `48h` time window; matches `^\d+[hdw]$` → time-window mode; contains a branch trigger word → branch mode; anything else → ask the user rather than guessing.

### Flag: `docs`

Append `docs` to any mode to include `.md` files in the sweep. By default, `.md` files are excluded because they're prose, not code. The `docs` flag tells the simplifier to review documentation for consistency — stale references, outdated library names, incorrect API examples, or references to renamed/removed code.

**When to use `docs`:**

- After a library migration — docs may reference old library names or patterns
- After a large refactoring — docs may reference old file paths, class names, or API shapes
- After renaming or reorganizing modules — docs may have stale cross-references

**Examples:** `/batch-simplify branch docs`, `/batch-simplify 72h docs`

**Detection:** if `$ARGUMENTS` contains the word `docs` (case-insensitive), set the docs flag and strip it before parsing the mode. The remaining argument determines time-window vs branch mode.

## Workflow

### Phase 1: Discover changed code files

Both modes union committed history with uncommitted changes (staged + unstaged) so nothing is missed.

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

### Phase 2: Filter to code files

Exclude non-code files. Keep only files that benefit from code simplification:

**Include** (code and code-like config):

- `.cs`, `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.py`, `.sh`, `.bash`, `.ps1`, `.psm1`, and any other source-code extensions the project uses
- Build-system config (`.csproj`, `.props`, `.targets`, `package.json`, `pyproject.toml`, and equivalents)
- Project config `.json` / `.jsonc` / `.toml` (e.g. `tsconfig.json`, `biome.json`, `.mcp.json` — not data files)
- Linter/format config (`.editorconfig`, `.gitattributes`, `.gitignore`, `.dockerignore`, `.shellcheckrc`)

**Exclude** (not useful for code simplification):

- `.md` files (documentation — prose, not code). **Exception:** when the `docs` flag is set, include `.md` files that are NOT in the protected list below. The simplifier reviews docs for stale references, outdated library names, incorrect API examples, or references to renamed/removed code — not for prose quality
- `.lock` files (`uv.lock`, `package-lock.json` — auto-generated)
- **Agent & enforcement configuration** — `.claude/hooks/**`, `.claude/settings*.json`, `.claude/agents/**`, `.mcp.json`, `.github/workflows/**`, git-hook manager config (`lefthook.yml`, `.husky/**`, `.pre-commit-config.yaml`): never handed to an autonomous simplifier (same safety model as this plugin's tidy skill). If they changed in the window, list them as read-only deferred items instead
- Data files (fixtures, datasets, exported records — anything that is content rather than logic)
- Skill/agent definition prose (`SKILL.md`, agent markdown), `README.md`, `CLAUDE.md`
- Generated or vendored code

**Append-only / historical-record protection** (applies even when the `docs` flag is set):

- **Filename patterns** (case-insensitive): `CHANGELOG.md`, `CHANGELOG.txt`, `HISTORY.md`, `RELEASES.md`, `NEWS.md`. ADR filenames matching `[0-9]{3,4}-*.md` under any `decisions/` or `adr/` directory (immutable post-acceptance by convention — supersede, do not edit the body).
- **Body-text declaration**: any file whose first 20 lines contain a case-insensitive match for `append-only`, `append only`, `historical record`, `do not edit historical entries`, or `immutable`. The declaration is the file declaring its own policy — honor it.
- **Why hard-excluded** (not a default-with-flag-override): a bulk find-replace on a changelog or accepted ADR rewrites history. Readers diffing the file later see what entries say NOW, not what they said when written. If a genuine update is needed, make a manual edit with explicit user authorization — do not bulk-include via the simplifier.

### Phase 3: Verify existence

Check each file exists on disk — files may have been deleted or renamed since the commit. Drop any that don't exist.

If no code files remain after filtering, report "No code files changed in {scope}" and exit (where scope is the time window or "branch vs default").

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

**Before spawning any agents**, ground the run: if the `discovery` plugin is installed, invoke `/discovery:explore` on the batch scope and `/discovery:research` covering idioms relevant to the dominant ecosystems in the wave; otherwise read representative files per group and do a focused inline research pass on the ecosystems' current idioms.

Waves can run in parallel when groups touch non-overlapping files and ecosystems. Launch independent groups in a single message with multiple Agent tool calls; serialize only when groups have direct dependencies.

For each group:

1. **Mark the task in_progress** via `TaskUpdate`

2. **Spawn a simplifier agent** via the `Agent` tool — use `subagent_type: "pr-review-toolkit:code-simplifier"` when that plugin is installed, else `subagent_type: "general-purpose"`. The prompt MUST include:
   - The complete list of files in the group (absolute paths)
   - The ecosystem and the consuming project's relevant convention files (its `CLAUDE.md` / `.claude/rules` paths), when they exist
   - Instructions to read each file and check for redundancy/inconsistency/dead code/simplification opportunities
   - Instructions to preserve ALL functionality (exit codes, output format, public API, CLI args)
   - The ecosystem-specific verification commands to run after changes (see context/reference.md)
   - An escalation clause: *"If you discover mid-task that the requested change is wrong, conflicts with project conventions, or requires touching files outside your file list, STOP and report back instead of improvising."*
   - **Deferral contract (required):** *"For every simplification you identify but choose NOT to apply, record it in a `## Deferred` section of your final report with this shape per item: `- <path>:<line or range> — <one-line description>. Reason: <why not now>. Scope: <trivial|small|medium|large>. Category: <refactor|dedup|modernize|perf|cleanup>.` Do not silently skip — if you noticed it, list it. This includes: (a) changes out of scope for this wave, (b) changes rejected for safety reasons, (c) changes that would trigger parallel-edit conflicts, (d) cross-file or cross-group refactors. 'Already idiomatic' or 'preserves documented contract' do NOT need to appear — only candidates you considered actionable but set aside."*

3. **Collect deferred items** — when the agent returns, extract the `## Deferred` section verbatim into a running list keyed by group number. Do not lose or paraphrase these items.

4. **Report results** — summarize what the agent changed (or didn't) for that group, plus a count of deferred items.

5. **Mark the task completed** via `TaskUpdate`

### Phase 6.5: Capture deferred items as issues

After all groups complete, consolidate the deferred items collected in Phase 6. NON-OPTIONAL — never silently defer: if you notice something and choose not to fix it now, say so and capture it.

1. **Dedupe and group** — multiple agents may flag the same cross-cutting concern. Merge into single items spanning all identified sites.

2. **Classify by priority:**
   - **High** — fits the current branch theme. File even if scope is large.
   - **Medium** — genuine tech debt, would dilute the current PR if bundled.
   - **Low** — nice-to-have, cross-cutting, low user-visible impact.
   - **Do-not-file** — genuine judgment calls where the agent's rationale is already a defensible answer. Still present to the user; do NOT drop silently.

3. **Present to the user** — before filing, show the consolidated list grouped by priority with proposed titles. Default to filing High + Medium automatically when running non-interactively; ask for Low and Do-not-file items.

4. **File work items** — one per deferred concern (not per site): via `/work-items:work-items add` when that plugin is installed, else `gh issue create` (or present the list when no tracker is reachable). Use Conventional Commits-style titles: `refactor(<area>): <what>`. The body should include the rationale the agent recorded, the specific files/lines, and the scope estimate.

5. **Record issue numbers** in the Phase 8 summary report so the user can cross-reference.

### Phase 7: Final cross-ecosystem verification

After all groups complete, run final verification across all affected ecosystems using the consuming project's canonical build/test/lint commands (its `CLAUDE.md` usually names them; generic fallbacks per ecosystem in [context/reference.md](context/reference.md) "Ecosystem verification commands (Phase 7)").

Simplification is behavior-preserving, so this objective cross-ecosystem pass is verification enough — a fresh-context verifier is the rule only where a verdict is subjective, not where the check is a mechanical pass/fail. A change that passes only because it altered behavior is a regression this final verification exists to catch (Gotchas).

Report the final verification results as a summary table.

### Phase 8: Summary report

Present a final report — scope + files-scanned + a per-group results table (`# | Group | Files | Changes | Deferred | Verification`) + final cross-ecosystem verdict + filed-issues and judgment-call-deferrals sections. Full template in [context/reference.md](context/reference.md) "Summary report template (Phase 8)".

If zero items were deferred across all groups, state explicitly: *"No items deferred. All identified simplifications were applied or determined to be no-ops."*

## Edge cases

- **No changes in time window**: report and exit cleanly
- **Single file changed**: still run the simplifier (skip grouping, just one group)
- **Agent reports no changes needed**: mark as "reviewed, no changes" — valid outcome. Still inspect the agent's output for a `## Deferred` section; zero applied changes does not mean zero deferrals
- **Agent reports deferrals**: non-optional path. Run Phase 6.5. Never paraphrase or collapse deferred items without presenting them to the user
- **Verification fails after simplification**: report the failure prominently — the agent should have caught this, but the final verification is the safety net
- **Very large groups (>25 files)**: split into sub-groups by subdirectory to keep the simplifier focused
- **Files that span multiple ecosystems**: group by the primary ecosystem (e.g., a `.sh` hook that invokes `ruff` goes in the shell group, not Python)
- **A consumer hook blocks subagent edits**: some projects gate edits behind precondition hooks (e.g., explore/research-first gates). Comply — satisfy the hook's precondition in the main session, then re-spawn the blocked groups. Do NOT bypass the hook via Bash workarounds and do NOT negotiate with it
- **Commits appear mid-run that this skill didn't make**: parallel sessions or auto-snapshot mechanisms may commit concurrently. `git log --oneline -5` reveals what was captured; treat those commits as authoritative for the changed state and proceed

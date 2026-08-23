---
description: "Manage git worktree lifecycle for parallel-session isolation: create (guided naming via EnterWorktree), status (PR + staleness inventory), cleanup (file-lock-aware removal), audit (infrastructure health). Use when: 'create worktree', 'worktree status', 'clean up worktrees', 'orphaned worktrees', or proactively when on main before writing code, not for PR lifecycle (use /pull-request)."
user-invocable: true
disable-model-invocation: false
argument-hint: "<action> [args] (e.g., /worktree create feat/my-feature, /worktree status, /worktree cleanup, /worktree audit)"
shell: bash
metadata:
  workflow-stage: session
  summary: Create, inspect, and clean git worktrees for parallel sessions
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Worktree inventory, `git worktree list | head -30`
- Git dir. `git rev-parse --git-dir`
- Git common dir (differs from the git dir when in a linked worktree).
  `git rev-parse --git-common-dir`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 30
entries") bounds nothing: the Bash tool returns the command's complete output into context before
there is anything to decide about. These are ordinary body Bash calls, not pre-compute, the shape
that #1619 is about is the harness composing the whole pre-compute block into one shell invocation.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. These moved
out of pre-compute in #1619, the harness composes the block into one shell invocation and a
worktree-isolated agent refuses a git-bearing compound command, which made the worktree skill itself
uninvocable from inside a worktree; do not fold them back.

That refusal is documented behavior, not a quirk of one release, so the constraint is durable. Per
[worktrees](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation) (fetched
2026-08-10), an isolated session's tool calls are screened by three checks. File edits into the main
checkout, a command whose **working directory** resolves there, and a **git redirect** into it
"whether through `git -C`, `--git-dir`, a `GIT_DIR` or `GIT_WORK_TREE` variable, or a `cd` into the
main checkout before running git". The two that bite a compound command are the last two, and both
fail closed: "Claude Code also blocks a command it can't verify stays inside the worktree." A block is
therefore not evidence the command *would* have reached the main checkout, an unverifiable one is
refused on the same footing, which is exactly what a multi-command shell invocation looks like. The
same page adds two facts worth holding: the enforcement "covers every subagent Claude spawns from the
isolated session, and it applies whether the session is interactive or runs in the background", so a
delegated worker inherits it rather than escaping it; and "For PowerShell commands, Claude Code
applies only the working-directory check", so PowerShell is narrower coverage, never a sanctioned
route around the git-redirect check.

## Purpose

Orchestrate git worktree lifecycle from creation through cleanup. **Front-half** of the development workflow. Gets you into a worktree and keeps them healthy. `/source-control:pull-request` is the **back-half**. Handles prep, PR creation, monitoring, merge.

**Why this exists:** worktrees are the isolation mechanism for parallel code changes. Multiple Claude Code sessions on different tasks without stepping on each other. In repos where branch protection blocks direct commits to main, every feature, fix, or refactor starts with a worktree or branch; this skill makes that seamless.

This skill is the canonical owner of the parallel-session worktree convention **for this plugin fleet**, and [§ The nesting invariant, verified](#the-nesting-invariant-verified) is the one site that states the mechanism, every other surface in this plugin points here instead of restating it. That is an ownership claim, not a census: consumer docs outside this repository also describe worktree placement, at least one of them written more recently than the as-of date below. So the ownership comes with an inbound channel, **a consumer that measures something contradicting that section should open an issue on this plugin's tracker so the owner is corrected here.** Canonical ownership with no back-channel just makes the owner the last to know.

Worktrees live at an external `worktree_root` (`<root>/<owner>-<repo>-<slug>`, outside every repository), defaulting to `<plugin-data-dir>/worktrees` when the key is unset, and never nested inside any repository's tree, that nesting invariant is what creation enforces, on the dated measured basis recorded below rather than as a standing absolute. Keeping `worktree_root` clear of repository-discovery roots (such as a ghq root) is convention, not machine-checked: creation rejects only paths inside an existing repository, so a root you point at a discovery tree still pollutes repository enumeration. `ghq list` reports each worktree as a repository of its own, and a leading dot does not hide it. Choose a configured root accordingly. The default is already clear of this: the plugin data directory is harness state, never a checkout and never inside a discovery tree, which a checkout-relative default would be under a layout like `<root>/github.com/<owner>/<repo>`.

### The nesting invariant, verified

**This section is the sole owner of the mechanism claim.** Every other statement of it in this plugin is a pointer here. It is a *dated measurement*, not a standing fact. Read the expiry below before relying on it.

The eager double-load this invariant was originally written against, CLAUDE.md, commands, agents, and rules all loading twice from a nested worktree, was fixed upstream in Claude Code v2.1.69, so that basis no longer holds. What replaces it, measured on 2.1.224: from a session inside a nested worktree, a read matching a `paths:` glob emits one `path_glob_match` naming the **parent** checkout's rule file, loading it alongside the worktree's own copy, both charged at roughly their own size. The same read from an externally-placed worktree emits zero such events. **That measurement is disputed, not refuted:** a later counter-reproduction on 2.1.227 did not observe the leak. Neither run disclosed its fixture, so the dispute is currently unadjudicable, which is what `fixtures/nesting-invariant-probe.sh` exists to end. A 2026-08-15 probe run on **2.1.232** pinned every discriminator the original runs omitted, but produced **zero `InstructionsLoaded` trace events on every arm** because the CLI was unauthenticated (`Not logged in`). That is a fixture failure, not a null finding. Do not cite this arm as settled in either direction. See `fixtures/README.md`.

**Three control arms narrow what the invariant actually rests on.** The leak is **not** specific to `.claude/worktrees/`: a worktree at a plain non-dot subdirectory leaks identically, so nesting inside the parent's tree is the cause and only placement outside it avoids the leak. A worktree nested inside an **unrelated** repository is worse, not better. It inherits **all three** surfaces, `CLAUDE.md` and unconditional rules at `session_start` as well as scoped rules. The mechanism behind that asymmetry: session-start ancestor traversal is suppressed for ancestors of the worktree's **own** repository but not for a **different** one, while `path_glob_match` discovery is suppressed in **neither**. That suppression rule is what the placement convention rests on, so a change to it is a recheck trigger in its own right. **Arm-by-arm status**, so a fix to one arm does not silently weaken another:

| Arm | Status |
|---|---|
| the leak exists at all on 2.1.224 | **disputed**. Unreproduced on 2.1.227; 2026-08-15 probe on 2.1.232 was inconclusive (fixture failure: hook never fired / CLI unauthenticated); neither original run disclosed its fixture |
| not specific to `.claude/worktrees/` | same status; the dot-vs-plain half is separately supported by the v2.1.69 changelog wording |
| **nested in an unrelated repo is worse** | **untested by anyone, and not refuted**, the 2026-08-15 run reached this arm's fixture but produced no trace; do not weaken it on the strength of the dispute above |
| lazy, not eager (no triggering read → no load) | untested |

Basis: an `InstructionsLoaded` hook trace, which names loaded files rather than inferring them from token deltas, passed via `claude -p --settings <file>` because project-scope hooks in an unapproved `settings.json` do not run headlessly. **The fixture is the adjudicator**. Creation mechanism, launch mode, the exact `paths:` glob and its anchoring root, and whether the parent's rule file was committed all change the outcome, and none of them was recorded for either original run. `fixtures/nesting-invariant-probe.sh` fixes all of them and is the recheck procedure; `fixtures/README.md` records what it has and has not established (including the 2026-08-15 inconclusive run).

On hook registration: use the `args`-array **exec form** here, per <https://code.claude.com/docs/en/hooks> (raw markdown, fetched 2026-08-11). "Set `args` whenever the hook references a path placeholder, since each element is passed as one argument with no quoting." That is the documented rule. An earlier version of this section claimed the single-string shell form "silently never fires"; **that is not what the docs say**, both forms are documented with no event-specific carve-out, and this plugin's own `hooks/hooks.json` registers all three of its hooks in the single-string form and they fire. The likeliest true cause of the original observation is a fixture-specific quoting or substitution failure generalized into a universal claim. Still unprobed by anyone, and therefore stated as unknown: whether the single-string form fires for an `InstructionsLoaded` hook supplied via `claude -p --settings <file>`.

Upstream coverage: [#16600](https://github.com/anthropics/claude-code/issues/16600) is the live issue. OPEN, labeled `enhancement` and `memory`, asking that memory traversal respect worktree boundaries. It concerns **memory files**; the same trace found those handled correctly on 2.1.224, so the surface still leaking is path-scoped rules, which no open upstream issue covers. That "handled correctly" is a **null result from this same trace**, not a release-note fact, no 2.1.224 changelog line covers memory, worktree, or rule loading, and that changelog scan is packet-sourced and has not been re-run. The two issues previously cited here are both CLOSED and neither is a recheck trigger any more: [#29599](https://github.com/anthropics/claude-code/issues/29599) (labeled `duplicate`, closed COMPLETED) reported the eager double-load that v2.1.69 fixed, and [#23565](https://github.com/anthropics/claude-code/issues/23565) closed NOT_PLANNED.

**Verification stamp** ([upstream-drift convention](../../../../docs/conventions/upstream-drift/README.md)), as-of **2026-08-07**, last adjudicated measurement on **2.1.224**. A 2026-08-15 probe attempt on **2.1.232** was inconclusive (fixture failure: CLI unauthenticated / zero `InstructionsLoaded` events) and does **not** refresh this stamp:

- **Recheck triggers (event).** A Claude Code release note naming worktree rule-file loading or path-scoped rule resolution; `#16600` changing state; or the suppression rule above changing, since the placement convention rests on it.
- **Unconditional expiry.** **2.1.244, or 2026-11-07. Whichever comes first.** Both event triggers are known to be incapable of firing on their own: `#16600` has not changed state since well before this as-of date, and an opaque release stanza ("Bug fixes and reliability improvements", 2.1.226) cannot fire an event-keyed trigger at all. An expiry is the only trigger that fires without upstream cooperation. On expiry, run `fixtures/nesting-invariant-probe.sh` under an **authenticated** CLI and refresh this stamp with the outcome. Drift or no drift. A zero-event run is a fixture failure, not a null.

## Adapting to your environment (graceful degrade)

This skill is self-contained, every action runs on plain `git`, plus `gh` for PR cross-referencing where available. Where it mentions an adjacent capability (an issue tracker, a build/lint verifier, a session-start setup hook), treat it as optional: use it when your environment provides it, proceed without it otherwise. Project-specific conventions, branch naming, worktree layout, which gitignored files a fresh worktree needs, come from the consuming project's own `CLAUDE.md`, rules, and hooks; read them before creating or removing anything.

## Arguments

`$ARGUMENTS`. Action selector. Parse first token as action, remainder as arguments.

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

   - **On the default branch** → "You're on `<default-branch>`. Create a branch (`git checkout -b <type>/<description>`) or use `/source-control:worktree create` if you need parallel session isolation."
   - **In a worktree** → Show current worktree info: branch name, last commit, associated PR (via `gh pr list --head <branch> --json number,title,state`). If a PR exists, suggest the next `/source-control:pull-request` phase.
   - **On a feature branch (not worktree)** → Show branch info and any associated PR.

5. **Check for stale/prunable worktrees**: Run a `git worktree list --porcelain` scan. If any worktrees are prunable or branches have merged PRs → suggest `/source-control:worktree cleanup`.

6. **Otherwise** → Show brief status summary (worktree count, any needing attention).

---

## Action: `create [name]`

Create a new worktree with guided naming and setup verification. Full procedure. Pre-flight guards (already-in-worktree, mid-session transition), name validation (EnterWorktree schema constraints), base-ref notes, the explain-before-create block, directory-rename caveats, and post-create setup checks: [context/create.md](context/create.md).

**Safety invariants create MUST honor** (full detail in context/create.md):

- **Create via the shared helper, not `EnterWorktree(name:)`.** `${user_config.worktree_root}` substitution into skill content is raw text, not shell-escaped, so it must never reach a shell parser, a value containing `'`, `$`, or a backtick breaks a quoted `--root` literal, and one containing the delimiter line ends a heredoc early. Instead write it to a temp file with the `Write` tool (JSON string parameter, never shell-parsed) and hand the file to the helper's `--fallback-root-file` flag (plugin-option rung, below `melodic.worktreeroot`); full render in [context/create.md § Create the worktree](context/create.md#create-the-worktree). The helper places the worktree at the external root (`<root>/<owner>-<repo>-<slug>`), copies `.worktreeinclude` files, and prints the path. `EnterWorktree(name:)` lands in the in-repo `.claude/worktrees/`, the placement [§ The nesting invariant, verified](#the-nesting-invariant-verified) exists to avoid.
- **On a non-zero helper exit, STOP, never fall back to `EnterWorktree(name:)`.** An unset `worktree_root` is no longer an error when another rung resolves: the helper may use `melodic.worktreeroot` or fall back to `<plugin-data-dir>/worktrees` from the value below and notes it on stderr, still exiting 0. Exit 3 means no usable root, neither configured nor supplied, a resolved root the containment guard rejects for landing inside a repository, **or** (on Windows) a root on a different drive from the repo, including the unconfigured plugin-data-dir default. Surface the helper's guidance and stop; a silent in-repo fallback is the nesting regression this closes.
- **Plugin data directory: `${CLAUDE_PLUGIN_DATA}`**, THIS FILE is the only surface where that token expands (a `context/` file is read as raw bytes and would carry it literally, and a Bash-tool subprocess's environment copy is not per-plugin). Carry the resolved path and hand it to the helper's `--data-root-file` flag through the same `Write`-tool temp file channel as the root above, so an unconfigured `worktree_root` still resolves to a location outside every repository. If the token ever arrives unexpanded, the helper detects it and refuses rather than creating a literally-named directory.
- **Enter with `EnterWorktree(path: "<printed-path>")` as the final action**, working directory changes and session state transitions on that call, so nothing may execute after it. The out-of-`.claude/worktrees/` path prompts for approval (not suppressible outside `bypassPermissions`).

**Orchestrated (autonomous) provisioning does not use this action.** An autonomous orchestrator that must stay resident to keep dispatching, e.g. `/work-items:work`, cannot invoke `create`: the `EnterWorktree` terminal above would transition the orchestrator's own session and end its ability to orchestrate. Such a run provisions **non-interactively** instead, the dispatched worker runs the shared `worktree-create.sh` helper directly (its output contract prints the path; the caller simply omits the `EnterWorktree` step) or a plain `git worktree add`, then works the worktree via `git -C <path>` **without entering it**. `#572` owns that end-to-end worker-side lifecycle.

---

## Action: `status`

Inventory all worktrees with PR association, staleness detection, and a **stranded-work axis**. Collect Tier-0 facts with plain git + gh (`git worktree list --porcelain` parse, one batched `gh pr list`, last-commit dates) plus one run of `${CLAUDE_PLUGIN_ROOT}/scripts/landed-work.sh` per repository, then apply the two-axis classification, staleness threshold (14-day default; the configured override is `${user_config.worktree_stale_days}`), and presentation schema per [context/status.md](context/status.md). `audit` Step 1 invokes this logic internally.

The **Work** axis answers a question age and PR state cannot: whether removing a worktree would destroy a commit. It is classified first and outranks the rest, so a worktree holding unpushed unlanded commits is `stranded`, never merely `stale`. An unprovable verdict reports `unknown` and is treated exactly as `stranded`, the engine reports `?` rather than `no` so that an ambiguity is never read as safe.

---

## Action: `cleanup [--dry-run]`

Remove stale worktrees, orphaned metadata, branches from merged PRs, and the project-scope plugin install records the worktree leaves behind. Full 5-step procedure. Prune orphaned metadata → identify candidates (4 detection reasons: orphaned dir / prunable / PR-merged / stale) → present → execute (4a release file locks, 4b guards → reap records → remove, 4c emit branch deletion for the user) → verify physical deletion: [context/cleanup.md](context/cleanup.md). `--dry-run` reports candidates and takes no action.

**Safety invariants cleanup MUST honor** (full detail in context/cleanup.md):

- **Never remove a worktree, and never emit its `git branch -D`, while its work is stranded or unproven**, a worktree whose unpushed commits are not already on the base loses them, and `unknown` is treated exactly as `stranded`. Both sites are guarded because removal itself is recoverable (the branch ref survives) while the branch deletion one step later is not; a detached-HEAD worktree is the exception where removal alone is already terminal. The override is `--acknowledge-stranded`, per worktree, never a bare `--force`, which answers git's dirty-tree check, a different question. Offer `git -C <path> push -u origin HEAD` first: it makes the commits durable without anyone judging whether the work matters.
- **Release OS file locks BEFORE `git worktree remove --force`** (Step 4a), on Windows `--force` unregisters the worktree from git but leaves a husk on disk if a process holds a file handle. Stop build servers (`dotnet build-server shutdown`, Gradle `--stop`, or your stack's equivalent) and worktree-rooted daemons/MCP servers first; stop ONLY those (never another live worktree's processes).
- **Reap the worktree's project-scope plugin install records BEFORE removing its directory, and only ever on a teardown this action is performing** (Step 4b). Claude Code keys a project-scope install to a literal `projectPath` and never reaps it when that path goes away, so a torn-down worktree leaves one record per installed plugin behind forever. Run `${CLAUDE_PLUGIN_ROOT}/scripts/reap-project-plugin-records.sh --worktree-path <path>` **from inside** the candidate, after the stranded-work and carried-file guards clear: `claude plugin uninstall -s project` has no path flag and resolves strictly against the current directory. **Never trigger a reap on bare path non-resolution.** A record for a live repository on an unmounted share or a detached volume looks identical to a dead worktree, and destroying it is unrecoverable. An **orphaned-directory** candidate is the strictest case, because it is the only class with no stranded-work row to read: it must pass **all four** of *not a symlink*, *not a work tree*, *no `.git` entry*, and *empty*. The middle test is the one that matters and the first does not imply it. A live worktree whose main clone was moved, deleted, or unmounted still carries its `.git` file while `rev-parse` fails, and the external root is shared across repositories, so such a directory is another lane's live work. Pre-existing orphans are `audit`'s to report, not this action's to remove.
- **A reap's non-zero exit is a no-op to report, never an escalation.** The CLI's failure text for an id with no project-scope record here suggests `--scope user`, which would uninstall the plugin fleet-wide. Never run `-s user`, never `--prune`, and never hand-edit `installed_plugins.json` (Claude Code's internal state, not a published contract).
- **Never swallow removal stderr** (`2>/dev/null`), a failed removal must surface so Step 5 reports husks honestly rather than counting one as removed.
- **Emit `git branch -D` + self-worktree removal for the USER to run, never inline** (Step 4c). Deleting a branch is destructive (and the consuming project's hooks may block it mid-session); a worktree can't delete itself (the running Claude Code session holds its handle). `-D` (not `-d`) is needed because squash-merge changes the SHA.

---

## Action: `audit`

Periodic health check for worktree infrastructure. Suitable as a recurring work item in your tracker. **Step 1:** run the `status` action internally, flagging any worktree whose Work axis is any value other than `safe` (see [context/status.md](context/status.md) for the closed mapping, do not re-enumerate here) and any whose Status shows an issue (stale, merged-not-cleaned, prunable, locked). Stranded work leads the findings, it is the only class where doing nothing is safer than acting. The Step 2 configuration-health checklist (`delete_branch_on_merge`, the `melodic.worktreeroot` conformance doctor, gitignored-file propagation), the Step 2b orphaned-plugin-install-record report, and the Step 3 findings presentation: [context/audit.md](context/audit.md).

**Step 2b reports; it never reaps.** Records left by worktrees removed before `cleanup` grew its reap step are not reachable by that step, so `audit` makes them visible, in four buckets: *live here*, *live elsewhere*, *candidate orphan*, and *other project records* (listed for information only with no remedy, because this plugin owns worktree lifecycle and nothing else). **The *live elsewhere* bucket is load-bearing and is the one an implementation drops:** the worktree root is shared: one root at `<root>/<owner>-<repo>-<slug>` serving every repository, so "not in *this* repository's `git worktree list`" is true of every other repository's live worktree under it. Registration is scoped to one repository; a liveness test (`git -C <path> rev-parse --is-inside-work-tree`) is not, and both are required before anything is called an orphan. Removing an orphan needs its directory recreated first, which is a deliberate user act; the audit emits the commands and stops. Reaping on bare path non-resolution is exactly what an unmounted volume looks like, and is never done.

---

## What this skill does NOT do

- **Does not push, create, merge, or close PRs**, `/source-control:pull-request` owns the back-half (prep, create, monitor, merge).
- **Does not commit or stage code**, staging and committing stay user-controlled; `/source-control:commit` owns the commit mechanic.
- **Does not run CI, build, test, or lint**, use your project's build/test/lint tooling or skills.
- **Does not manage remote branches**, GitHub's `delete_branch_on_merge` handles remote cleanup on merge (when enabled); local `git branch -D` is emitted for the user, never run inline.
- **Does not uninstall plugins, and does not touch user or local scope.** `cleanup`'s reap removes only the *project-scope install records keyed to the worktree it is tearing down*, through `claude plugin uninstall -s project`. It never runs `-s user` or `-s local`, never passes `--prune`, and never edits `installed_plugins.json`. Fleet-wide plugin state is a plugin-management concern, not a worktree one.
- **Does not enforce branch naming**, the consuming project's hooks and CI are the gates. This skill only surfaces the project's convention (read it from the project's `CLAUDE.md` / rules; default suggestion: `<type>/<kebab-description>` with a Conventional Commits type prefix).

## Integration Points

This skill complements other workflow components. It does not duplicate their logic.

| Component | Relationship |
|-----------|-------------|
| `/source-control:pull-request merge` (Phase 4) | Handles post-merge cleanup as part of PR lifecycle. `/source-control:worktree cleanup` is the standalone version for ad-hoc or batch cleanup |
| `/source-control:pull-request create` (Phase 2.1) | Detects default-branch checkout and suggests `/source-control:worktree create` |
| Project session-start hooks (if any) | May warn on main or auto-configure fresh worktrees; this skill verifies setup ran per context/create.md's post-create checks |
| Recurring maintenance tracker items | Can invoke `/source-control:worktree audit` periodically |

## Graceful Degradation

- **`gh` CLI unavailable or fails**: `status` and `cleanup` work with git-only data. PR cross-reference and the `delete_branch_on_merge` check are skipped with note: "GitHub API unavailable. PR status unknown."
- **Not in a git repo**: All actions exit immediately with "Not in a git repository."
- **`worktree_stale_days` invalid or unexpanded**: Falls back to 14-day default silently (treat a literal `${user_config.worktree_stale_days}` token as unset).
- **No worktrees exist**: `status` reports "No linked worktrees found." `cleanup` reports "Nothing to clean up."

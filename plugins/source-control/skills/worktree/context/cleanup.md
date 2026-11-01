# Worktree `cleanup`: full 5-step procedure

`<scripts-dir>` is the scripts directory resolved in SKILL.md. This file is read as raw bytes, so substitute that resolved absolute path for `<scripts-dir>` before a command reaches Bash.

Full detail for `/source-control:worktree cleanup [<path>...] [--dry-run]`. SKILL.md carries the headline and the safety invariants; this file carries the full procedure (prune → identify → present → execute → verify), including the Windows file-lock handling and the Step 4b branch deletion.

## Scope: explicit paths or the whole repository

Settle the scope before Step 1. Strip `--dry-run` from the arguments; what remains are worktree paths.

- **Paths given.** Scope is exactly those worktrees. Resolve each against `bash "<scripts-dir>/lib/worktree-facts.sh" list <repo>` (a path that is not a registered linked worktree of this repository, or is the primary checkout, is reported and dropped, never falling through to the sweep). Run the Step 2 classification, the stranded-work record and every Step 4 guard on those rows only. **Skip** the repository-wide inventory, the Step 2 detection scan for other candidates, and the `worktree-root-scan.sh` root scan. Every named worktree is presented in Step 3 with its classification even when it matches no Step 2 reason (e.g. a young worktree with an open PR): naming it is the request, so the user confirms or declines, and the guards still decide whether removal may proceed. Step 1's `git worktree prune` still runs, since it touches only records of directories already gone.
- **Bare `cleanup`, session worked one worktree.** When this session created a worktree, entered one with `EnterWorktree`, or merged a PR from one, and that worktree is a linked worktree of this repository, ask before inventorying: "Clean up only `<path>` (branch `<branch>`), or sweep the whole repository?" Offer the single worktree as the default, the sweep as the alternative. If the session worked more than one worktree, list them and ask which, with the sweep last. On the single-worktree answer, continue as for named paths; on the sweep answer, continue as below. An unattended run with no one to answer takes the single worktree, never the sweep.
- **Bare `cleanup`, no worktree worked.** The whole-repository behavior below, unchanged; also the behavior when the sweep is chosen.
- **The scoped worktree is the one the session runs in.** Compare the scoped path to `git rev-parse --show-toplevel`. When they match, say so before anything else: "`<path>` is this session's own worktree." Classification and guards run as usual, with no repo-wide inventory, and Step 4b decides how its removal runs.

### Outside a repository: across repositories

When `git rev-parse --is-inside-work-tree` fails, cleanup acts on every repository that owns a worktree, one repository at a time, with the single-repository steps unchanged. Every git command in Steps 1 to 5 runs as `git -C '<owning-repo>' …`: the prunes, `worktree unlock`, `worktree remove`, `branch -D`, the emitted `push origin --delete`, and the four Workspace-entry reads `down` depends on ([create.md § Workspace environment setup](create.md#workspace-environment-setup)). Each forge read (PRs, `delete_branch_on_merge`) targets the owning repository, each helper that takes `--repo-dir` gets `'<owning-repo>'`, and the carried-file guard's `MAIN_ROOT` is the owning repository. A step that needs a working directory, such as `down`, runs in a subshell `( cd '<dir>' && … )`, so the caller's working directory never changes. A path or repository holding a single quote reaches no command: report it.

`down` is the one step this mode gates further. Discovery collects every repository with a worktree under the roots, including clones the user never chose to trust, and a session outside every repository has no stage context for Step 4a's untrusted-input skip. So `down` runs for an owning repository only when its exact command line and source commit SHA appeared under that repository's heading in the Step 3 table the user confirmed. Step 4a runs that shown command, never one re-read later. A repository whose `down` was not shown has `down` skipped: report it as skipped and say why, as the untrusted-input rule does.

1. **Collect.** Run `worktree-discover.sh` as [status.md § Outside a repository](status.md#outside-a-repository-cross-repository-mode) does and keep its rows. Each `repo` row whose linked count is above 0 is an owning repository. A named path takes its owning repository from its `worktree` row and is then resolved against `worktree-facts.sh list '<owning-repo>'` as the paths-given scope above does; a path with no row, or with owner `-`, is reported and dropped.
2. **Identify.** Run Step 1 and Step 2 once per owning repository, including its own stale batch and stranded-work record. In place of Step 2's per-repository root scan, run the Step 2c root scan of [audit.md](audit.md) once per `root` row, with `--root '<root>'` and every `repo` row as a `--repo-dir`; its proposed rows have no owning repository and are listed under their root. With paths given, skip the root scan and the detection scan as the paths-given scope does. A `worktree` row with owner `-` is reported, never a candidate.
3. **Present.** Show one Step 3 table with a heading per owning repository (scan rows under their root) and end it with one confirm covering every group, naming each repository the yes acts on. Under each heading that has a git-tracked candidate, read the Workspace entry as [create.md § Workspace environment setup](create.md#workspace-environment-setup) step 2 does, against `'<owning-repo>'`, and show its `down` command line verbatim with the commit SHA, or `down: none` when no entry or no `down` line is found. The confirm states that a yes also runs each `down` command shown. `--dry-run` stops here, after Step 1's `--dry-run` prunes, having removed nothing.
4. **Remove.** Run each confirmed worktree through Step 4a and 4b against its owning repository; Step 4b's `<main-root>` is the owning repository. This session's own worktree cannot be a candidate here, since the session runs outside every repository. A scan row has no owning repository: it takes its class's qualifying tests, the file-lock release, the reap and the `rm -rf`, as in a single-repository run.
5. **Verify.** Run Step 5 once per owning repository, and report per repository.

A stranded, superseded, unknown, in-progress or dirty row stops exactly as it does in a single-repository run, and the other repositories' rows go on.

## Step 1: Prune orphaned metadata

```bash
git worktree prune
```

Cleans up administrative records for worktree directories no longer on disk (e.g., deleted via `rm -rf`).

A **locked** worktree's record survives `prune` even when its directory is gone; git does this deliberately, and it makes the lock a durable claim. Surface such records (a row of `bash "<scripts-dir>/lib/worktree-facts.sh" list <repo>` with `locked=yes` whose `path` no longer exists) rather than counting them pruned: apply the **Stale lock** test from Step 2 (the merged or landed check needs the branch name from the `branch` column), or otherwise confirm with the owner, then `git worktree unlock <path>` (works with the directory missing) and prune again.

In `--dry-run` mode this step runs `git worktree prune --dry-run` instead, which reports what would be pruned without touching worktree metadata, keeping the whole dry run mutation-free.

## Step 2: Identify cleanup candidates

Run `status` logic internally and identify candidates:

| Reason | Detection method |
|--------|-----------------|
| **Orphaned directory** | A row of `bash "<scripts-dir>/worktree-root-scan.sh" --repo-dir <each canonical repo>` classed `empty` or `husk`: a directory under a worktree root that no repository registers. Only a row the scan proposes (`proposed` = `yes`) is a candidate: `empty`, or a `husk` whose only entry is its `.git` file. Each must also pass its class's qualifying tests in Step 4a, run again at removal, and a `husk` is removed only after those tests and then the file-lock release, both in Step 4a. A `husk` row with other content, and `foreign`, `live`, `symlink` and `unknown` rows, are never candidates: report them. Those tests are not optional: the external root is shared across repositories, so another repository's live worktree is absent from this one's list, and a live worktree whose main clone is unreachable fails the `rev-parse` test while still holding all its work: it is `unknown`, never a `husk`. Scan every root your project uses. Common layouts: (1) the **configured external root** (`worktreeroot.path`, then the `worktree_root` plugin option, then the plugin data dir) where `create` actually places every worktree, and which is shared across repositories; (2) `<repo-root>/.worktrees/`; (3) Claude Code's default `<repo-root>/.claude/worktrees/`; (4) bare-clone hub `<hub-root>/<name>/`, siblings of `.bare/`, found by detecting the hub (`git rev-parse --git-common-dir` ends in `.bare`) and resolving `<hub-root>` as its parent (same detection the Smart Default and `create` pre-flight use). Empty shells remain when Claude Code's built-in cleanup removes worktree contents but the directory husk persists, from a terminal kill without clean exit OR a file lock blocking deletion (release per Step 4a, after its guards and class tests pass). Safe to remove once unlocked |
| **Prunable** | The `prunable` column of `bash "<scripts-dir>/lib/worktree-facts.sh" list <repo>` is `yes` |
| **PR merged** | The forge lists a merged PR for the branch ([GitHub](../../../reference/providers/github/README.md#resolve-a-pull-request)) |
| **Stale** | Last commit > threshold days, no open PR, no locked flag. A `pr-unknown` row (PR lookup incomplete) is never Stale |
| **Reap age** | Proposed by default only when ALL hold: the row is a linked worktree (`linked=yes` in `worktree-facts.sh list`, so never the primary checkout or a bare hub); Work is `safe`; Status is `merged` **or** the engine shows zero unpushed commits (`unpushed=0`); last-commit age exceeds `worktree_reap_after_hours` (`status.md` data-collection step 4); and, when the worktree is locked, its row of the stale batch below the table has exit `0`, the liveness proof a **Stale lock** needs. Every helper-created worktree is locked at creation, so this is the common case; a lock that proof does not cover (this session's own, a live lane's, another host's) keeps the row **Locked**: report it, never propose it. `stranded`, `superseded`, `unknown`, `in-progress`, `dirty` and `notgit` rows are never proposed by this reason, however old. Every Step 4 guard still runs on an accepted row, and a locked one is confirmed and unlocked as Step 4a describes |
| **Stranded** | `landed-work.sh` reports `risk=STRANDED` or `risk=UNKNOWN`. **Not a cleanup candidate.** Listed here because it is the row most easily mistaken for `Stale`: both are old and quiet, but this one holds unpushed commits whose content is not on the base |
| **In-progress operation** | `landed-work.sh` reports `risk=in-progress`, or its `inprogress` column is anything but `none`. **Not a cleanup candidate.** A rebase, merge, cherry-pick, revert, or bisect is mid-flight, probed via `git rev-parse --git-path` (`rebase-merge`, `rebase-apply`, `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `BISECT_LOG`). Clean does not mean idle: an interactive rebase paused at a `break` leaves `git status --porcelain` empty, and plain `git worktree remove` then deletes it silently, since git refuses only dirty trees. Report the operation; the owner finishes or aborts it first |
| **Locked** | `bash "<scripts-dir>/lib/worktree-facts.sh" list <repo>` shows `locked=yes` (with or without a reason) and neither the **Stale lock** test below nor the locked case of **Reap age** holds. **Not a cleanup candidate.** `worktree-create.sh` and `worktree-claim.sh` both encode that reason through `worktree_lock_reason`. Present the reason; only on explicit confirmation that the owner is done, disarm with `git worktree unlock <path>` and re-classify. Never bypass with `--force --force` |
| **Stale lock** | Locked, **and** the branch's PR is merged (the forge lists a merged PR for the branch) or `landed-work.sh` reports `risk=landed`, **and** its row of the stale batch below the table has exit `0`. That verb is read-only, and the row's note is the evidence line (no live session transcript for the lane that armed the lock); exit `1` means liveness is unproven, so the row stays **Locked**. A candidate, but only behind the Step 4 confirmation gate: present the lock reason and the evidence line, and on yes run `git worktree unlock <path>` (the caller is not the owning session, so `worktree-claim.sh release`, which refuses a foreign lock, does not apply), then the plain removal. Never `--force --force` |

**Stale batch.** Prove liveness for every locked row of a repository in one call, never one call per row:

```bash
printf '%s\0' '<locked-path-1>' '<locked-path-2>' | bash "<scripts-dir>/worktree-claim.sh" stale --batch --repo-dir '<repo>'
```

It prints one `exit<TAB>path<TAB>note` row per path, in input order, with the exit code and note that `stale <path>` gives for that path: `0` provably stale (the note is the evidence line), `1` not provable, `5` not a registered worktree. A locked row stays **Locked** when its exit is anything but `0`, its path is missing from the output, or the call itself exits non-zero (`2` usage, `5` not a repository), since that run proved nothing. Single-quote each path. A path holding a single quote never goes into the command, and its row stays **Locked**.

Take the branch name from the `branch` column of `bash "<scripts-dir>/lib/worktree-facts.sh" list <repo>`, not the directory name, which may differ if the branch was renamed.

Collect the stranded-work record in the same pass, per `status.md`'s data-collection step 5: one run per repository, joined on `path`. Every guard below reads its `risk` column, so a candidate list built without it cannot be executed safely.

## Step 3: Present candidates

```markdown
## Cleanup Candidates

| # | Worktree | Branch | Reason |
|---|----------|--------|--------|
| 1 | <worktree-root>/old-fix | fix/old-thing | PR #18 merged 5d ago |
| 2 | <worktree-root>/moonlit-popping-pike | none | Orphaned directory (scan class `empty`, no git ref) |
| 3 | (orphaned metadata) | none | Directory no longer exists |
| 4 | <worktree-root>/old-lane | feat/old-lane | Reap age (nothing unpushed, last commit 3d ago); locked: `lane active on <host> session <id> since <utc>`; stale: session <id> on <host> has no transcript change in 120 minutes |

**Action:** Remove these 4 items and delete their local branches? (yes/no/select)
```

That yes is the confirmation Step 4b relies on, so the prompt names what it authorizes: on Linux and macOS, deleting each removed worktree's local branch with `git branch -D` and, when this session's own worktree is listed, removing it (name its path). On Windows, where Step 4b emits those commands for the user, ask only "Remove these N items?".

## Step 4: Execute or report

- **`--dry-run`**: Report candidates only, take no action. Exit.
- **Otherwise**: Ask for confirmation with the Step 3 prompt. On "yes", record free space first (below), then run each candidate through phases 4a → 4b. 4a runs the guards first, then the file-lock release, the Workspace `down`, the reap and the removal; a row any guard keeps has no side effects: no process is stopped and nothing is reaped.

**Free space before removal.** Step 5 reports the disk the run gave back, so take the first
reading before any removal, on a directory the removal leaves in place: the worktree root holding
each candidate (the candidate's parent directory), one `df -Pk '<worktree-root>'` per distinct
filesystem among those roots. Single-quote each root so the shell expands nothing: the configured
root may hold `$` or a backtick. A root containing a single quote never goes into a command: report
it and omit its reading. Never point `df` at a candidate's own directory: it is gone after Step 5,
and `df` on a missing path exits non-zero. `-P` keeps each filesystem on one line, `-k` reports
1024-byte blocks, and the `Available` column is the number to keep. Note which roots you read,
because Step 5 runs the identical commands. In PowerShell, `(Get-PSDrive -Name <letter>).Free` for
each root's drive gives the same figure in bytes.

### Step 4a: Guards, then remove the worktree

```bash
# Orphaned directory (scan class `empty`, or `husk` proposed `yes`): remove it —
# ONLY after it has passed every qualifying test for its class below. Absence
# from `git worktree list` is NOT on its own a license to run this line.
rm -rf <path>

# Git-tracked worktree — plain removal first. It FAILS on a dirty worktree
# specifically to prevent data loss; never blind-escalate past that.
git worktree remove <path>
```

**The session's own worktree is deferred.** When the candidate path equals `git rev-parse --show-toplevel`, skip only the `git worktree remove` line here; Step 4b removes it before deleting its branch. Both guards, the file-lock release, the workspace `down` and the reap still run here, in the order below, while the directory is on disk: the reap takes `--worktree-path <path>` and enters it itself, so it cannot follow the removal, and plain removal loses gitignored files with exit 0.

**Two guards, the file-lock release, the workspace `down` and one reap run before ANY removal, plain or forced, in this order: guard 1 → guard 2 → file-lock release → `down` → reap → removal.** For a locked candidate, the `worktree-claim.sh stale` proof (exit 0) is part of guard 2: it is a read-only check, and a row where it fails is kept before the release, `down` and the reap. The guards only read state, so a row any guard keeps has no side effects: no process is stopped, no `down` runs and nothing is reaped. The file-lock release and `down` follow the guards so a worktree they keep keeps its processes and services. The stranded-work guard runs first because it can abort the removal outright; running the carried-file comparison first would reconcile files for a worktree that won't be removed, and an aborted removal loses nothing that needed syncing. The reap runs last before the removal for the inverse reason: the process stop and the reap are *not* undoable, so neither may fire for a worktree the guards are about to save.

**1. Stranded-work guard:** removal itself is recoverable (`git worktree remove` unregisters the directory and leaves the branch ref intact), but a detached-HEAD worktree has no branch ref holding its commits, and for every other candidate the `git branch -D` that Step 4b runs (Linux and macOS) or emits for the user (Windows, or when a hook blocks it) finishes the job one step later. This guard covers both while the candidate is still on disk.

Read the candidate's row from the record collected in Step 2:

- `risk=landed`, `ok`, or `bare` → proceed.
- `risk=STRANDED`, `UNKNOWN`, or `superseded` → **stop and do not remove.** Present the count, the `base` stamp, the `reason`, and the commit subjects (`git -C <path> log HEAD --not --remotes --oneline`), then get explicit per-worktree confirmation naming those commits. `UNKNOWN` means the engine could not prove landedness, not that it proved absence. `superseded` means only that a MERGED pull request carried this branch's NAME; a name reused after that merge makes the evidence describe different commits than these, and the row is `landed=no` either way. Treat both exactly as `STRANDED`.
- `risk=in-progress` → **stop.** A merge, rebase, cherry-pick, revert, or bisect is mid-flight here. Its staged tree is recomputable, but the operator's conflict resolutions are not, and the operation's position is lost with the directory. The tree can be completely clean too: an interactive rebase paused at a `break` leaves `--porcelain` empty, which is why this row outranks `landed` and never reads as disposable. Report the operation and let the user finish or abort it first.
- `risk=dirty` → **stop.** Nothing is unpushed, but the working tree carries uncommitted edits; the same value is emitted when the working-tree status could not be read at all (the `-` or `?` in the count columns). Neither is safe to remove without the user looking.
- **Any value not listed above → treat it as `STRANDED`.** The list is closed on the safe side only: an unrecognized risk value is one this file cannot vouch for, and an unproven verdict never authorizes a removal.
- When the row's `peers` column names another worktree, say so: those commits survive in the peer, which is a different decision from losing them.
- The override is `--acknowledge-stranded`, per worktree, never a bare `--force`. `--force` answers git's dirty-tree check, a different question, and one flag must not silently answer both.

An absent field prints as the literal `-`, never as nothing (a blank would collapse under tab-splitting and shift every later column). Present `-` as "not resolved" rather than verbatim: a `base` of `-` means no base was resolved, which is exactly why the row is `UNKNOWN`.

Offer the non-destructive resolution first: `git -C <path> push -u origin HEAD` makes the commits durable and reclassifies the row as safe without anyone judging whether the work matters.

**2. Carried-ignored-file guard:** `git worktree remove`
succeeds on a worktree whose only edits are gitignored files, which `status --porcelain` does not
show, so plain removal silently discards them. When the repo root has a `.worktreeinclude`, run
the same per-pattern comparison as `/source-control:pull-request create`'s pre-flight, expanding each pattern from
the worktree toplevel (skip unmatched globs) AND from `MAIN_ROOT`, before removing. Differing or
new carried file → offer the copy-to-main sync; main-side file ABSENT in the worktree → offer
removing main's copy only on explicit confirmation of a deliberate deletion (default keep, since the
file may simply never have been carried). Removal without this pass loses the edits with exit 0.

**File-lock release (Windows-critical).** Once both guards have cleared, and for a locked candidate once `bash "<scripts-dir>/worktree-claim.sh" stale <path>` has exited 0 (run for that candidate just before its release, not read from the Step 2 batch, and after any owner-is-done confirmation, as the Escalation guard below describes; any other exit keeps the row, with nothing stopped), release the candidate's OS file locks. `git worktree remove --force` overrides git's dirty/locked-worktree check but does NOT release OS file handles: on Windows any process holding a file under the worktree blocks directory deletion ("Permission denied" / "being used by another process"), and `--force` then unregisters the worktree but leaves a husk on disk. Stop the processes rooted in the candidate's path:

- **Build servers** holding compiled output, e.g. `dotnet build-server shutdown` (.NET / VBCSCompiler + MSBuild), Gradle `--stop`, or your stack's equivalent. They hold bin/output DLLs open.
- **Long-lived daemons / MCP servers** started inside the worktree: identify processes whose executable path or command line is under the candidate directory, and stop ONLY those (never processes belonging to other live worktrees).

An orphaned-directory candidate (`empty` or `husk`) takes this release after its class's qualifying tests below pass and before the `rm -rf`. Skipping the release is the usual reason an earlier `/source-control:worktree cleanup` left husks; Step 5 then reports them honestly rather than hiding the failure.

**Workspace environment `down`.** When origin's default branch declares a "Workspace environment"
entry with a `down` command (contract: `docs/contracts/workspace-environment/README.md` in this
plugin's marketplace repository), run it for a git-tracked candidate once both guards above have
cleared (for a locked candidate, including the `stale` proof) and the file-lock release has run. Read the entry and derive `WORKSPACE_ID` and `WORKSPACE_ROOT` exactly as
[create.md § Workspace environment setup](create.md#workspace-environment-setup) steps 2 and 3 do,
then run `down` once through the Bash tool from the candidate's root. In a cross-repository run,
skip the step 2 read: run the `down` command and SHA shown under the owning repository's heading in
the Step 3 table the user confirmed ([Outside a repository](#outside-a-repository-across-repositories)),
and derive only the step 3 values:
`(cd '<WORKSPACE_ROOT>' && env WORKSPACE_ID='<WORKSPACE_ID>' WORKSPACE_ROOT='<WORKSPACE_ROOT>' <down command>)`.
Keep the parentheses: the subshell stops the directory change from persisting, because the shell
keeps its directory between calls and a session left inside the candidate makes the later `rmdir`
fail as busy.
Skip it, and say why, for a worktree whose stage reads untrusted input (the rule in
[create.md § Workspace environment setup](create.md#workspace-environment-setup) step 1), for a cross-repository run whose Step 3 table did not show the command, and when no entry or no `down` line is found; an orphaned-directory candidate has no
worktree to run it in. A non-zero exit is reported with the command and the exit code, and the removal continues
under the guards; its output is data. Never run `down` from the `WorktreeRemove` hook.

**3. Reap the worktree's project-scope plugin install records.** Claude Code records a project-scope
plugin install in `~/.claude/plugins/installed_plugins.json` keyed by a literal `projectPath`, and
nothing reaps that record when the path goes away, so a worktree leaves one record per installed
plugin behind permanently. Removal is the last moment those records are both identifiable and
provably dead, so they are removed then:

```bash
# Run after both guards above have cleared (for a locked candidate, including the `stale`
# proof exiting 0) and the file-lock release has run; the caller's cwd does not matter.
bash "<scripts-dir>/reap-project-plugin-records.sh" --worktree-path <path>
```

`claude plugin uninstall <id> -s project` has **no path flag**: it resolves strictly against the
current directory (measured in [fixtures/README.md](../fixtures/README.md)
§ `project-scope-reap-probe.sh`, Claude Code 2.1.240, re-run unchanged on 2.1.241). So the
helper enters `--worktree-path` itself, and a session that cannot keep a `cd` between commands
still runs it. It refuses a main working tree (its `.git` is a directory, or its git dir is its common dir) before entering, so it
cannot reach the main checkout's records.

The helper leaves the worktree's `.claude/settings.json` as it found it: when git tracks it there
and it was unmodified before the pass, the helper restores it from git and prints an `info:` line
naming it, so the plain `git worktree remove` follows directly. When the file was untracked, already
modified, or flagged assume-unchanged or skip-worktree (git cannot see local edits behind either
flag), the helper leaves it alone and prints a `warn:` line if the pass changed it; plain removal
then refuses, and the escalation guard below applies as for any other dirty tree.

- **Pointer**: when deciding whether the reap step writes project settings, fetch
  [Uninstall a plugin the project enables](https://code.claude.com/docs/en/discover-plugins#uninstall-a-plugin-the-project-enables)
  live; correlate with issue #6007 for the side effects that section does not cover.
  **As of**: 2026-10-13. **Recheck trigger**: a Claude Code release changes plugin uninstall, or the
  helper's restore stops firing on real teardowns.

Five rules govern this step; each closes a way it could do real harm:

- **The trigger is this teardown, never path liveness.** Reap a worktree *this cleanup is removing*,
  never "a path that does not currently resolve": a project-scope record for a live repository
  on an unmounted network share or detached external volume is indistinguishable from a dead
  worktree to a bare existence check, and destroying those records is unrecoverable data loss. Pre-existing orphans from worktrees removed before this step existed are **reported by
  `audit`, not reaped here**. See [audit.md](audit.md).
- **A non-zero exit is a no-op to report, never an escalation.** The CLI's own failure text for an id
  with no project-scope record here reads `Plugin "<id>" is installed in user scope, not project.
  Use --scope user to uninstall.` Following that suggestion would uninstall the plugin **fleet-wide**.
  Never run `-s user`, and never `--prune` (which reaches past project scope into shared
  auto-installed dependencies).
- **Every uninstall carries `--keep-data`, and the helper passes it unconditionally.** The CLI
  deletes a plugin's `${CLAUDE_PLUGIN_DATA}` directory when the uninstalled scope was its last, so
  without the flag this step destroys stored state of plugins it only meant to un-record, and the
  report cannot show it happened. This step
  reaps records; a record is not data.
- **Never hand-edit `installed_plugins.json`.** It is Claude Code's internal state, not a published
  contract. Every removal goes through the CLI; the helper only reads the file, and only to report
  survivors.
- **A degrade is reported, not swallowed.** Exit 3 (no `claude` on PATH, no `jq`, or enumeration
  failed) means the records survive the removal: say so and continue with the removal. Exit 1 means
  some record survived the pass: surface it. The zero case (`no records recorded here`) is reported
  too, so "nothing to reap" is never indistinguishable from "never checked".

`--dry-run` never reaches this step: Step 4 reports the candidates and exits before any guard runs or any process is stopped. The
helper has its own `--dry-run` for a manual check from inside a worktree; it names what would be
removed and calls nothing.

**The orphaned-directory candidate takes this step too, behind the qualification below, which is
stricter than anything else in this file.** It is a directory this action is destroying, which is
the trigger, but also the only candidate class with **no stranded-work row to read**. The
engine enumerates strictly from `worktree-facts.sh list` (see [status.md](status.md) data
collection), so an unregistered directory produces no row, and guard 1's closed-list rule
covers an unrecognized *value*, never an *absent row*. For this class the qualification below is the
only gate between a live directory and an unrecoverable reap plus `rm -rf`.

**Precondition on the scan itself.** If a configured worktree root does not resolve to a directory
right now, do not scan or classify anything under it: the volume is detached, and every path under
it would qualify on identical evidence.

**Normalize `<path>` FIRST, stripping every trailing separator, and run every test against the
normalized form.** POSIX pathname resolution forces a trailing-slash path to resolve *through* a
symlink to a directory, so `test -L "link/"` reports **false** for a symlink and the disqualifier
below silently passes. Measured on this plugin's own host
(Git Bash, native symlinks): `test -L link` → true, `test -L "link/"` → **false**, and
`find link -mindepth 1` → **empty**, because `find` does not descend a symlinked start point either.
A candidate string with one trailing character therefore looks like an empty non-symlink and
sails into `rm -rf`. Pinned by `scripts/reap-project-plugin-records.test.sh`.

```bash
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)   # Windows shells: `\` is a separator here, and only here
    while [[ "$path" == */ || "$path" == *'\' ]]; do path="${path%?}"; done ;;
  *)                      # POSIX: `\` is a legal filename byte — strip `/` only
    while [[ "$path" == */ ]]; do path="${path%?}"; done ;;
esac
```

The loop is the rule rendered as code: `${path%/}` alone strips **one forward slash**, leaving a
Windows-pasted trailing backslash (the common form on the platform the measurement above came
from) or a doubled separator, and either survivor re-opens the bypass. The platform gate
matters in the other direction: off Windows a trailing `\` is part of the directory's
**name** (the same gated rule `scripts/worktree-create.sh` applies to its root normalization), so
stripping it there would re-point every test below, and the reap plus `rm -rf`, at a sibling
path while leaving the actual candidate behind.

**Four tests, ALL of which must hold** for an `empty` row, against that normalized `<path>`. The first
three are negatives and prove nothing alone; the last is the only positive evidence available,
and it is what the presentation row's "(scan class `empty`, no git ref)" claims:

```bash
test -L "<path>"                                             # must be FALSE — not a symlink
git -C <path> rev-parse --is-inside-work-tree 2>/dev/null    # must NOT print `true`
test -e "<path>/.git"                                        # must NOT exist (file OR directory)
find "<path>" -mindepth 1 | head -1                          # must return NOTHING (read the output, not the status)
```

0. **Not a symlink.** Tested on the normalized path (above); `test -L "<path>/"` answers
   about the *target*, not the link. `find <path> -mindepth 1` does not descend a symlinked start
   point, so a link to a busy directory reports **empty** and passes test 3, while the reap, which
   resolves `pwd` through the link, would act on the *target's* records. A symlink is never a husk
   this action created: disqualify and report it.
1. **Not a work tree.** `true` means the directory belongs to some repository, not necessarily this
   one. The external worktree root is **shared**: `create` places worktrees at
   `<root>/<owner>-<repo>-<slug>`, one root serving every repository on the machine
   (`reference/worktree-root-convention.md` for the root; `scripts/worktree-create.sh` for the
   `<owner>-<repo>-<slug>` naming), so a scan of that root turns up other repositories' live
   worktrees, every one of them absent from *this* repository's list.
2. **No `.git` entry. This is the test that actually matters, and test 1 does not imply it.** A live
   worktree whose main clone has been moved, deleted, or unmounted still carries its `.git` **file**
   while `rev-parse` fails, so test 1 alone calls another lane's live worktree a husk and destroys
   it. A `.git` entry present, resolvable or not, disqualifies an `empty` row outright.
3. **Empty.** A husk is empty; a worktree is not. Nothing else in this action tests this, and without
   it "orphaned directory" is inferred from two failures rather than observed. Read the
   **output**, never the exit status: `find … | head -1` exits 0 whether or not it printed anything,
   so a status check would call every directory empty.

**A `husk` row takes tests 0 and 1 unchanged and replaces tests 2 and 3.** It has a `.git` entry by
definition, so test 2 cannot apply; in its place is positive evidence that git itself dropped
the registration while its main clone is intact. A worktree whose main clone was moved, deleted, or
unmounted has no `<common>` to show, so it is `unknown` and stays out (`git worktree repair` from the
recovered clone re-points it without losing anything). Test 3 becomes "nothing but the `.git` file":
with the registration gone no `git status` can vouch for any other entry, which may be uncommitted
work (e.g. a worktree moved by hand and then pruned). A husk holding anything else is reported
and left alone. Read the **output** of the last line, never its status:

```bash
test -f "<path>/.git" && ! test -L "<path>/.git"             # a regular file
sed -n 's/^gitdir: //p' "<path>/.git"                        # names <common>/worktrees/<name>
test -e "<gitdir>"                                           # must NOT exist: the admin dir is gone
test -f "<common>/HEAD" && test -d "<common>/objects"        # must hold: <common> is still a repository
ls -A "<path>"                                               # must print exactly `.git`
```

A candidate failing any test for its class is **not** an orphaned directory. Report it as another
lane's worktree, or as a directory whose contents nobody has accounted for, and leave it entirely
alone: do not reap, do not remove. Deriving deadness from the negatives alone is the inference
[audit.md](audit.md) refuses on the same evidence, and the acting path may not be more permissive
than it.

**Escalation guard (before any `--force`):** when plain removal fails, inspect why: `git -C <path> status --porcelain` (uncommitted edits) and `git -C <path> log HEAD --not --remotes --oneline | head` (unpushed commits). `HEAD`, not `--branches`: on a detached HEAD, the one case where removal makes commits unreachable *immediately* with no branch ref left holding them, `--branches` reports every other branch in the repository and nothing about this worktree's own commits, so the guard reads clean exactly when it matters most. If either is non-empty, present the summary and get explicit per-worktree confirmation BEFORE forcing, since forced removal permanently discards those changes. Only after confirmation (or when the failure is a lock/metadata issue with a verifiably clean tree):

```bash
git worktree remove --force <path>   # dirty-tree override — only after the confirmation above
```

A **locked** worktree never takes the second `--force`. The lock is an owning lane's claim, armed
at creation by `worktree-create.sh`, not a stronger kind of dirt, and `--force --force` answers
both questions with one flag. Only a **Stale lock** or a locked **Reap age** row (Step 2) is removable at all, and both need `bash "<scripts-dir>/worktree-claim.sh" stale <path>` exiting 0. Any other locked worktree stays.

On explicit confirmation that the owner is done, first re-run `bash "<scripts-dir>/worktree-claim.sh" stale <path>` (the owning session may have resumed while the confirmation was pending). It is the same proof guard 2 requires in the order above, so run it after the confirmation and before the release, `down` or reap. If it no longer exits 0, stop and leave the tree locked with nothing stopped, released or reaped. Only when it still exits 0, run the file-lock release, `down` and the reap once, in that order (never a second release), then run
`git worktree unlock <path>`, then remove (plain, or a single `--force` only for a
confirmed-dirty tree). The unlock is a separate deliberate act naming the lock, so no flag
silently answers a question it was not asked.

Do NOT swallow stderr with `2>/dev/null`. A failed removal must surface so Step 5 can report it honestly.

### Step 4b: Branch + current-worktree deletion (run inline on POSIX, emit on Windows or a hook block)

```bash
git -C '<main-root>' worktree remove '<current-worktree-path>'    # first, only if the active worktree was itself a candidate
git -C '<main-root>' branch -D --end-of-options '<branch-name>'   # second: -D needed (squash-merge changes SHA); git refuses while the branch is still checked out in a worktree
```

Substitute `<branch-name>`, `<main-root>` and `<current-worktree-path>` only when each is safe to quote: a branch name matches `^[A-Za-z0-9._/-]+$`, does not start with `-` and holds no `..`; a path holds no single quote. Keep the single quotes. Any other value reaches no command: report it as data, because untrusted input can shape git ref names and paths.

**Where it runs.** The Step 4 confirmation is the user's go-ahead. With it given and both Step 4a guards (stranded-work and carried-ignored-file) passed for the row, and the workspace `down` and the reap already run there:

- **Linux and macOS (`uname -s` is not `MINGW*`, `MSYS*` or `CYGWIN*`): run both commands yourself.** A process's working directory can be removed on these systems while it runs, so the session's own worktree is removable and the session carries on from a directory that still exists (run later commands with `git -C` on the main checkout, or by absolute path). Run the worktree removal first and the branch deletion after, both through `git -C '<main-root>'` as in the block above (the branch stays checked out, and so undeletable, while its worktree exists). The removal is for the session's own worktree, which Step 4a defers here; every other candidate was already removed in Step 4a, after its guards. Unlock first only for a row the Step 4a lock rules allow.
- **Windows: emit them for the user.** The running Claude Code process holds the session worktree's directory handle there, so the worktree cannot delete itself. Surface the commands to run from a main-repo terminal (or via the `!` prompt prefix) instead of running them.
- **A hook blocks a command, on any host: stop, report the block and the command, and emit it for the user.** Try the command and report a block; never route around a hook, and never retry the same command.

**The stranded-work precondition applies here too, and this is where it bites hardest.** Removal left the branch ref intact; this line is what destroys the commits. Run or emit the `git branch -D` line only for a branch whose row was `landed` or `ok`. For `STRANDED`, `UNKNOWN`, or `superseded`, run and emit nothing and say why. A suggested command in a code block reads as vetted, and a user pasting it cannot know the guard was never applied to it. Emit `git -C <path> push -u origin HEAD` instead.

The branch this deletes may also be checked out by another worktree; `git branch -D` refuses then, which is git protecting the peer, not an error to work around.

Remote branch cleanup is not needed when the repo has `delete_branch_on_merge` enabled (GitHub deletes the remote branch on merge). Read the repository's `delete_branch_on_merge` setting ([GitHub](../../../reference/providers/github/README.md#branch-rules)); otherwise also emit (remote deletion is always emitted, never run inline) `git push origin --delete --end-of-options '<branch-name>'`, only for a name that matches `^[A-Za-z0-9._/-]+$`, does not start with `-` and holds no `..`; any other name is reported, never emitted.

## Step 5: Verify physical deletion, prune, and report

```bash
git worktree prune   # clears admin metadata for working trees now missing
```

`git worktree prune` clears metadata but cannot delete a husk a process still holds, so verify each removed candidate's directory is actually gone:

```bash
test -d <path> && echo "HUSK REMAINS: <path>" || echo "removed: <path>"   # PowerShell: Test-Path <path>
```

`prune` and `repair` are complementary; do not confuse them. `git worktree prune` discards admin metadata for a worktree whose directory is genuinely gone. `git worktree repair` re-points metadata when the directory still exists but was moved by something other than `git worktree move` (see [create.md](create.md) directory-renaming caveats). A *moved* worktree can look prunable here; if the directory landed elsewhere and should stay registered, repair it (`git help worktree`) instead of pruning its registration.

Report honestly, and never count a husk as removed:

- **Fully removed**: directory gone AND metadata pruned.
- **Unregistered, husk remains**: `git worktree list` is clean but the directory is still on disk (a lock survived Step 4a). Surface the path; the user removes it after closing the holding process.

- **Records reaped**: the count the reap step returned per candidate, plus any it could not remove.
  A record that survived, or a reap that degraded (exit 3), is named with its path so the user can
  re-run the helper from a directory recreated there; it is never quietly dropped.

- **Disk freed**: run the identical `df -Pk '<worktree-root>'` (or `Get-PSDrive`) commands from
  Step 4, on the same worktree roots, never on a removed candidate's directory, and report the free space before, after, and the difference. Other processes write to the
  same disk during cleanup, so call the difference approximate; a husk that remains holds its
  space until the user removes it.

Report: "Removed N worktrees (M fully deleted, K husks remaining, paths above); reaped R project-scope plugin install records; free space on <filesystem> went from X to Y (about Z freed). Run `/source-control:worktree status` to verify."

**macOS build caches.** On a macOS host (`uname -s` prints `Darwin`) where `command -v xcrun`
resolves, read [macos-caches.md](macos-caches.md) after this report and follow it: it measures the
Xcode build cache and unavailable simulators and deletes an item only on its own yes. On any other
host, or when `xcrun` does not resolve, skip it and do not mention it. `--dry-run` never reaches
this step.

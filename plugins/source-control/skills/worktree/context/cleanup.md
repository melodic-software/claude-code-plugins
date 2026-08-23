# Worktree `cleanup` — full 5-step procedure

Full detail for the `/source-control:worktree cleanup [--dry-run]` action. SKILL.md carries the headline plus the safety invariants; this file carries the complete step-by-step (prune → identify → present → execute → verify), including the Windows file-lock handling and the user-emitted branch deletion.

Remove stale worktrees, orphaned metadata, and branches from merged PRs.

## Step 1: Prune orphaned metadata

```bash
git worktree prune
```

Cleans up worktree administrative records for directories that no longer exist on disk (e.g., manually deleted via `rm -rf`).

A **locked** worktree's record survives `prune` even when its directory is gone — deliberate on git's part, and what makes the lock a durable claim. Surface such records (a `locked` stanza in `git worktree list --porcelain` whose path no longer exists) rather than counting them pruned: confirm with the owner, then `git worktree unlock <path>` (works with the directory missing) and prune again.

In `--dry-run` mode this step runs `git worktree prune --dry-run` instead — it reports what would be pruned without touching worktree metadata, keeping the whole dry-run pass mutation-free.

## Step 2: Identify cleanup candidates

Run `status` logic internally and identify candidates:

| Reason | Detection method |
|--------|-----------------|
| **Orphaned directory** | Directory exists under a worktree root but NOT in `git worktree list` output — **and** it passes all four qualifying tests in Step 4b (not a symlink, not a work tree, no `.git` entry, empty). Those tests are not optional: the external root is shared across repositories, so another repository's live worktree is absent from this one's list, and a live worktree whose main clone is unreachable fails the `rev-parse` test while still holding all its work. Scan every root your project uses — common layouts: (1) the **configured external root** (`melodic.worktreeroot`, then the `worktree_root` plugin option, then the plugin data dir) where `create` actually places every worktree, and which is shared across repositories; (2) `<repo-root>/.worktrees/`; (3) Claude Code's default `<repo-root>/.claude/worktrees/`; (4) bare-clone hub `<hub-root>/<name>/` — siblings of `.bare/`, found by detecting the hub (`git rev-parse --git-common-dir` ends in `.bare`) and resolving `<hub-root>` as its parent (same detection the Smart Default + `create` pre-flight already use). Empty shells are left when Claude Code's built-in cleanup removes worktree contents but the directory husk persists — from terminal kill without clean exit, OR a file lock blocking deletion (release per Step 4a first). Safe to remove once unlocked |
| **Prunable** | `git worktree list --porcelain` shows `prunable` flag |
| **PR merged** | `gh pr list --state merged --head <branch>` returns non-empty result |
| **Stale** | Last commit > threshold days, no open PR, no locked flag |
| **Stranded** | `landed-work.sh` reports `risk=STRANDED` or `risk=UNKNOWN` — **not a cleanup candidate.** Listed here because it is the row most easily mistaken for `Stale`: both are old and quiet, but this one holds unpushed commits whose content is not on the base |
| **In-progress operation** | `landed-work.sh` reports `risk=in-progress`, or its `inprogress` column is anything but `none` — **not a cleanup candidate.** A rebase, merge, cherry-pick, revert, or bisect is mid-flight, probed via `git rev-parse --git-path` (`rebase-merge`, `rebase-apply`, `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `BISECT_LOG`). Clean does not mean idle: an interactive rebase paused at a `break` leaves `git status --porcelain` completely empty, and plain `git worktree remove` then deletes it silently — git's own refusal covers dirty trees and nothing else. Report the operation; the owner finishes or aborts it first |
| **Locked** | `git worktree list --porcelain` shows a `locked` line (reason on the same line) — **not a cleanup candidate.** `worktree-create.sh` arms the lock on every worktree it creates, so a lock is an owning lane's claim, and the reason names the creator, host, and start time. Present the reason; only on explicit confirmation that the owner is done, disarm with `git worktree unlock <path>` and re-classify — never bypass with `--force --force` |

Extract actual branch name from porcelain output (`branch refs/heads/<name>`), not from directory name — they may differ if branch was renamed.

Collect the stranded-work record in the same pass, per `status.md`'s data-collection step 5 — one run per repository, joined on `path`. Every guard below reads its `risk` column, so a candidate list built without it cannot be executed safely.

## Step 3: Present candidates

```markdown
## Cleanup Candidates

| # | Worktree | Branch | Reason |
|---|----------|--------|--------|
| 1 | <worktree-root>/old-fix | fix/old-thing | PR #18 merged 5d ago |
| 2 | <worktree-root>/moonlit-popping-pike | — | Orphaned directory (empty, no git ref) |
| 3 | (orphaned metadata) | — | Directory no longer exists |

**Action:** Remove these 3 items? (yes/no/select)
```

## Step 4: Execute or report

- **`--dry-run`**: Report candidates only, take no action. Exit.
- **Otherwise**: Ask for confirmation. On "yes", run each candidate through phases 4a → 4b → 4c.

### Step 4a: Release file locks first (Windows-critical)

`git worktree remove --force` overrides git's dirty/locked-worktree check but does NOT release OS file handles. On Windows, any process holding a file under the worktree blocks directory deletion ("Permission denied" / "being used by another process") — `--force` then unregisters the worktree from git but leaves a husk on disk. Before removing a candidate, stop the processes rooted in its path:

- **Build servers** holding compiled output — e.g. `dotnet build-server shutdown` (.NET / VBCSCompiler + MSBuild), Gradle `--stop`, or your stack's equivalent. They hold bin/output DLLs open.
- **Long-lived daemons / MCP servers** started inside the worktree — identify processes whose executable path or command line is under the candidate directory, and stop ONLY those (never processes belonging to other live worktrees).

Skipping 4a is the usual reason a previous `/source-control:worktree cleanup` left husks behind — Step 5 then reports them honestly rather than hiding the failure.

### Step 4b: Remove the worktree

```bash
# Orphaned directory: remove the husk — ONLY after it has passed all four
# qualifying tests below (not a symlink, not a work tree, no `.git` entry,
# empty). Absence from `git worktree list` is NOT on its own a licence to run
# this line.
rm -rf <path>

# Git-tracked worktree — plain removal first. It FAILS on a dirty worktree
# specifically to prevent data loss; never blind-escalate past that.
git worktree remove <path>
```

**Two guards and one reap run before ANY removal, plain or forced, in this order: guard 1 → guard 2 → reap → removal.** The stranded-work guard first, because it can abort the removal outright — running the carried-file comparison ahead of it spends work reconciling files for a worktree that is not going to be removed, and an aborted removal loses nothing that needed syncing. The reap runs last of the three for the same reason inverted: it is the only one of the three that is *not* undoable, so it must not fire for a worktree the guards are about to save.

**1. Stranded-work guard:** removal itself is recoverable — `git worktree remove` unregisters the directory and leaves the branch ref intact — but a detached-HEAD worktree has no branch ref holding its commits, and for every other candidate the `git branch -D` emitted in Step 4c finishes the job one step later. Both are covered here, at the point where the candidate is still on disk.

Read the candidate's row from the record collected in Step 2:

- `risk=landed`, `ok`, or `bare` → proceed.
- `risk=STRANDED`, `UNKNOWN`, or `superseded` → **stop and do not remove.** Present the count, the `base` stamp, the `reason`, and the commit subjects (`git -C <path> log HEAD --not --remotes --oneline`), then get explicit per-worktree confirmation naming those commits. `UNKNOWN` means the engine could not prove landedness, not that it proved absence. `superseded` means only that a MERGED pull request carried this branch's NAME — a name reused after that merge makes the evidence describe different commits than the ones here, and the row is `landed=no` either way. Treat both exactly as `STRANDED`.
- `risk=in-progress` → **stop.** A merge, rebase, cherry-pick, revert, or bisect is mid-flight here. Its staged tree is recomputable, but the operator's conflict resolutions are not, and the operation's position is lost with the directory. The tree can be completely clean at the same time — an interactive rebase paused at a `break` leaves `--porcelain` empty, which is why this row outranks `landed` and never reads as disposable. Report the operation and let the user finish or abort it first.
- `risk=dirty` → **stop.** Nothing is unpushed, but the working tree carries uncommitted edits — and the same value is emitted when the working-tree status could not be read at all, which is the `-` or `?` you will see in the count columns. Neither is safe to remove without the user looking.
- **Any value not listed above → treat it as `STRANDED`.** The list is closed on the safe side only. A risk value this file does not recognize is a value it cannot vouch for, and the whole point of the record is that an unproven verdict never authorizes a removal.
- When the row's `peers` column names another worktree, say so: those commits survive in the peer, which is a different decision from losing them.
- The override is `--acknowledge-stranded`, per worktree, never a bare `--force`. `--force` answers git's dirty-tree check, which is a different question, and one flag must not silently answer both.

An absent field prints as the literal `-`, never as nothing (a blank would collapse under tab-splitting and shift every later column). Present `-` as "not resolved" rather than verbatim — a `base` of `-` means no base was resolved, which is exactly why the row is `UNKNOWN`.

Offer the non-destructive resolution first — `git -C <path> push -u origin HEAD` makes the commits durable and reclassifies the row as safe without anyone having to judge whether the work matters.

**2. Carried-ignored-file guard:** `git worktree remove`
succeeds on a worktree whose only edits are gitignored files — `status --porcelain` does not show
them, so plain removal silently discards them. When the repo root has a `.worktreeinclude`, run
the same per-pattern comparison as `/source-control:pull-request create`'s pre-flight — expand each pattern from
the worktree toplevel (skip unmatched globs) AND from `MAIN_ROOT` — before removing. Differing or
new carried file → offer the copy-to-main sync; main-side file ABSENT in the worktree → offer
removing main's copy only on explicit confirmation of a deliberate deletion (default keep — the
file may simply never have been carried). Removal without this pass loses the edits with exit 0.

**3. Reap the worktree's project-scope plugin install records.** Claude Code records a project-scope
plugin install in `~/.claude/plugins/installed_plugins.json` keyed by a literal `projectPath`, and
nothing reaps that record when the path goes away. A worktree therefore leaves one record per
installed plugin behind, permanently — measured on this convention's own author machine: 108
project-scope records, across 8 marketplaces, every one of them naming a single worktree directory
that no longer exists. Removing the directory is the last moment at which those records are both
identifiable and provably dead, so removal is where they are removed too:

```bash
# Run FROM INSIDE the candidate, after both guards above have cleared.
cd <path> && bash "${CLAUDE_PLUGIN_ROOT}/scripts/reap-project-plugin-records.sh" --worktree-path <path>
```

The `cd` is not incidental. `claude plugin uninstall <id> -s project` has **no path flag**: it
resolves strictly against the current directory (measured — [fixtures/README.md](../fixtures/README.md)
§ `project-scope-reap-probe.sh`, Claude Code 2.1.240, re-run unchanged on 2.1.241). The helper
enforces the same thing from the other side: it refuses unless `--worktree-path` names the directory
it is already standing in, so it structurally cannot act on any path but its own.

Four rules govern this step, and each closes a way it could do real harm:

- **The trigger is this teardown, never path liveness.** Reap a worktree *this cleanup is removing*.
  Never reap "a path that does not currently resolve": a project-scope record for a live repository
  on an unmounted network share or a detached external volume is indistinguishable from a dead
  worktree to a bare existence check, and destroying those records is unrecoverable data loss for
  the user. Pre-existing orphans from worktrees removed before this step existed are **reported by
  `audit`, not reaped here** — see [audit.md](audit.md).
- **A non-zero exit is a no-op to report, never an escalation.** The CLI's own failure text for an id
  with no project-scope record here reads `Plugin "<id>" is installed in user scope, not project.
  Use --scope user to uninstall.` Following that suggestion would uninstall the plugin **fleet-wide**.
  Never run `-s user`, and never `--prune` (which reaches past project scope into shared
  auto-installed dependencies).
- **Never hand-edit `installed_plugins.json`.** It is Claude Code's internal state, not a published
  contract. Every removal goes through the CLI; the helper only ever reads the file, and only to
  report survivors.
- **A degrade is reported, not swallowed.** Exit 3 (no `claude` on PATH, no `jq`, or enumeration
  failed) means the records survive the removal — say so and continue with the removal. Exit 1 means
  some record survived the pass; surface it. The zero case (`no records recorded here`) is reported
  too, so "nothing to reap" is never indistinguishable from "never checked".

`--dry-run` never reaches this step — Step 4 reports the candidates and exits before phase 4a. The
helper carries its own `--dry-run` for a manual check from inside a worktree; it names what would be
removed and calls nothing.

**The orphaned-directory candidate takes this step too — behind the qualification below, which is
stricter than anything else in this file.** It is a directory this action is destroying, which is
the trigger; but it is also the only candidate class with **no stranded-work row to read**. The
engine enumerates strictly from `git worktree list --porcelain` (see [status.md](status.md) data
collection), so an unregistered directory produces no row at all, and guard 1's closed-list rule
covers an unrecognized *value*, never an *absent row*. For this class the qualification below is the
only gate standing between a live directory and an unrecoverable reap plus `rm -rf`.

**Precondition on the scan itself.** If a configured worktree root does not resolve to a directory
right now, do not scan it and do not classify anything under it. The volume is detached, and every
path under it would qualify on identical evidence.

**Normalize `<path>` FIRST — strip every trailing separator — and run all four tests against the
normalized form.** This is not tidiness. POSIX pathname resolution forces a trailing-slash path to
resolve *through* a symlink to a directory, so `test -L "link/"` reports **false** for something that
is a symlink, and the disqualifier below silently passes. Measured on this plugin's own host
(Git Bash, native symlinks): `test -L link` → true, `test -L "link/"` → **false**, and
`find link -mindepth 1` → **empty**, because `find` does not descend a symlinked start point either.
A candidate string carrying one trailing character therefore looks like an empty non-symlink and
sails into `rm -rf`. Pinned by `scripts/reap-project-plugin-records.test.sh`.

```bash
path="${path%/}"        # and again for a Windows-style trailing backslash
```

**Four tests, ALL of which must hold**, against that normalized `<path>`. The first three are
negatives and prove nothing on their own; the last is the only positive evidence available, and it is
what the presentation row's "(empty, no git ref)" has always claimed:

```bash
test -L "<path>"                                             # must be FALSE — not a symlink
git -C <path> rev-parse --is-inside-work-tree 2>/dev/null    # must NOT print `true`
test -e "<path>/.git"                                        # must NOT exist (file OR directory)
find "<path>" -mindepth 1 | head -1                          # must return NOTHING (read the output, not the status)
```

0. **Not a symlink** — tested on the normalized path, per the note above; `test -L "<path>/"` answers
   about the *target*, not the link. `find <path> -mindepth 1` does not descend a symlinked start
   point, so a link to a busy directory reports **empty** and passes test 3 — while the reap, which
   resolves `pwd` through the link, would act on the *target's* records. A symlink is never a husk
   this action created; disqualify it and report it.
1. **Not a work tree.** `true` means the directory belongs to some repository — not necessarily this
   one. The external worktree root is **shared**: `create` places worktrees at
   `<root>/<owner>-<repo>-<slug>`, one root serving every repository on the machine
   (`reference/worktree-root-convention.md` for the root; `scripts/worktree-create.sh` for the
   `<owner>-<repo>-<slug>` naming), so a scan of that root turns up other repositories' live
   worktrees, every one of them absent from *this* repository's list.
2. **No `.git` entry. This is the test that actually matters, and test 1 does not imply it.** A live
   worktree whose main clone has been moved, deleted, or unmounted still carries its `.git` **file**
   while `rev-parse` fails — so test 1 alone calls another lane's live worktree a husk and destroys
   it. A `.git` entry present, resolvable or not, disqualifies the candidate outright.
3. **Empty.** A husk is empty; a worktree is not. Nothing else in this action tests this, and without
   it "orphaned directory" is an inference from two failures rather than an observation. Read the
   **output**, never the exit status: `find … | head -1` exits 0 whether or not it printed anything,
   so a status check would call every directory empty.

A candidate failing any of the four is **not** an orphaned directory. Report it as another lane's
worktree, or as a directory whose contents nobody has accounted for, and leave it entirely alone:
do not reap, do not remove. Deriving deadness from the negatives alone is exactly the inference
[audit.md](audit.md) refuses to make on the same evidence, and the acting path may not be the more
permissive of the two.

**Escalation guard (before any `--force`):** when the plain removal fails, inspect why — `git -C <path> status --porcelain` (uncommitted edits) and `git -C <path> log HEAD --not --remotes --oneline | head` (unpushed commits). `HEAD`, not `--branches`: on a detached HEAD — the one case where removal makes commits unreachable *immediately*, with no branch ref left holding them — `--branches` reports every other branch in the repository and nothing about this worktree's own commits, so the guard reads clean at exactly the moment it matters most. If either is non-empty, present the summary to the user and get explicit per-worktree confirmation BEFORE forcing — forced removal permanently discards those changes. Only after confirmation (or when the failure is a lock/metadata issue with a verifiably clean tree):

```bash
git worktree remove --force <path>   # dirty-tree override — only after the confirmation above
```

A **locked** worktree never takes the second `--force`. The lock is an owning lane's claim — armed
at creation by `worktree-create.sh` — not a stronger kind of dirt, and `--force --force` answers
both questions with one flag. On explicit confirmation that the owner is done:
`git worktree unlock <path>` first, then remove (plain, or a single `--force` only for a
confirmed-dirty tree). The unlock is a separate deliberate act naming the lock, so no flag ever
silently answers a question it was not asked.

Do NOT swallow stderr with `2>/dev/null` — a failed removal must surface so Step 5 can report it honestly.

### Step 4c: Emit branch + current-worktree deletion for the user (do not run inline)

Branch deletion is destructive (and the consuming project's hooks may block `git branch -D` mid-session), and the worktree a session runs in cannot delete itself — the running Claude Code process holds its directory handle. Surface these for the user to run from a main-repo terminal (or via the `!` prompt prefix) rather than executing them inline:

```bash
# Run from main repo / another terminal:
git branch -D <branch-name>                    # -D needed (squash-merge changes SHA)
git worktree remove <current-worktree-path>    # only if the active worktree was itself a candidate
```

**The stranded-work precondition applies here too, and this is where it bites hardest.** Removal left the branch ref intact; this line is what actually destroys the commits. Emit `git branch -D <branch-name>` only for a branch whose row was `landed` or `ok`. For `STRANDED`, `UNKNOWN`, or `superseded`, emit nothing and say why — a suggested command in a code block reads as vetted, and a user pasting it has no way to know the guard upstream was never applied to it. Emit `git -C <path> push -u origin HEAD` instead.

The branch this deletes may also be checked out by another worktree; `git branch -D` refuses in that case, which is git protecting the peer rather than an error to work around.

Remote branch cleanup is not needed when the repo has `delete_branch_on_merge` enabled (GitHub deletes the remote branch on merge) — check via `gh api repos/{owner}/{repo} --jq .delete_branch_on_merge`; otherwise also emit `git push origin --delete <branch-name>`.

## Step 5: Verify physical deletion, prune, and report

```bash
git worktree prune   # clears admin metadata for working trees now missing
```

`git worktree prune` clears metadata but cannot delete a husk a process still holds, so verify each removed candidate's directory is actually gone:

```bash
test -d <path> && echo "HUSK REMAINS: <path>" || echo "removed: <path>"   # PowerShell: Test-Path <path>
```

`prune` and `repair` are complementary — do not confuse them. `git worktree prune` discards admin metadata for a worktree whose directory is genuinely gone. `git worktree repair` re-points metadata when the directory still exists but was moved by something other than `git worktree move` (see [create.md](create.md) directory-renaming caveats). A *moved* worktree can look prunable to this step; if the directory landed elsewhere and should stay registered, repair it (`git help worktree`) rather than pruning its registration away.

Report honestly — never count a husk as removed:

- **Fully removed** — directory gone AND metadata pruned.
- **Unregistered, husk remains** — `git worktree list` is clean but the directory is still on disk (a lock survived Step 4a). Surface the path; the user removes it after closing the holding process.

- **Records reaped** — the count the reap step returned per candidate, plus any it could not remove.
  A record that survived, or a reap that degraded (exit 3), is named with its path so the user can
  re-run the helper from a directory recreated there; it is never quietly dropped.

Report: "Removed N worktrees (M fully deleted, K husks remaining — paths above); reaped R project-scope plugin install records. Run `/source-control:worktree status` to verify."

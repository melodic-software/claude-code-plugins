# Refresh a formal-area skill

The steps of `/formal-verification:specify refresh`, in order. A formal check proves a property of
what it describes. When the code changes and the verification does not, the check can keep passing
while it describes code that no longer exists. That pass is the dangerous case, because it looks
like a proof. This is the upkeep loop for a `formal-<area>` skill that `create` generated, or for any
project-local skill that runs a model checker, prover, or code-level verifier against named code.
The `formal-<area>` skill handles a change that an agent makes while it uses that skill. Refresh
handles the changes that skipped it: merges, edits made without the skill, and drift that builds up
across many commits.

## Contents

- Outcomes
- Edit scope
- Before the pass
- Pass
- Verification skills outside the contract
- Bugs
- Commit
- Report

## Outcomes

Give each check one outcome, and say which:

- **in sync**: no change since the last sync alters what the check describes, and the check passes.
- **updated**: the code changed, the verification now describes the new code, and the check passes.
- **bug**: the verification describes the current code, and the code breaks the property. This is a
  finding about the code. It is not drift.
- **blocked**: the check could not be brought back in line or could not run. Say exactly why.

A check can be both updated and bug: the update makes the verification describe the code again, and
then the property fails on it.

## Edit scope

Edit only the verification: models, harnesses, property files, and the `formal-<area>` skill
itself. Never edit product code during a run, unless the user asks you to. When a property fails on
the current code, do not weaken the property or the model to make it pass. Report the failure.

Steps 2 to 5 run in a throwaway git worktree, never the person's working tree; step 6 alone writes,
and only the `formal-<area>` folder, the paths its `sync.yaml` lists under `outside_model`, and a
conversion path named with `--convert`.

An unattended run (`--unattended`, or no person present) runs every step, but step 6 writes only for
a check that ends `in sync` or `updated` with its seeded break caught. A proposed property change, a
`bug` and a `blocked` outcome get no verification edit: they go in the report.

## Before the pass

1. Resolve the settings: `node "<plugin-root>/scripts/settings.mjs" --project-dir "$PWD"`, with
   `<plugin-root>` as the skill renders it. `skills_dir` is where `formal-<area>` folders live.
2. Record where the pass starts: `git branch --show-current`, or, when that prints nothing,
   `git rev-parse HEAD`. Read the default branch's name with `git ls-remote --symref <remote> HEAD`
   and fetch it, `git fetch <remote> <name>`, `<remote>` being `origin`, else the only remote. The
   fetched commit (`FETCH_HEAD`) is the tip for the whole pass. When the read or fetch fails, every
   check is `blocked` with git's stderr line.
3. Name the start: the default branch, an upkeep branch `formal-verification-upkeep/<folder>`, or a
   detached HEAD at the tip (the pass commits on the upkeep branch), a ticket branch, which is any
   other branch (it commits there), or a detached HEAD off the tip (it commits nothing).
4. Choose the commit checked, for each `formal-<area>` folder. On a start that takes the upkeep
   branch it is the tip; on a detached HEAD off the tip it is `HEAD`. On a ticket branch it is the
   merge base with the tip when the ticket's own diff
   (`git diff --name-only <merge base> HEAD`) touches no covered path; otherwise it is `HEAD`, and
   that folder's sync commit stays where it is, to move in a follow-up change after the ticket lands.
   A sync commit is always a commit on the default branch.

## Pass

1. **Find the checks.** A verify skill has no fixed name, so find it by what it does: a project skill
   that runs a model checker, a prover, or another verifier against named code. Read each one you
   find under `skills_dir`, or the folders the user named. `/formal-verification:specify check` names
   the folders that hold a `sync.yaml` or `model/` outside the contract; those follow "Verification
   skills outside the contract" below. For each check, collect the property (`## Property`), the code
   it covers (`covers`), the bounds and assumptions (`## Bounds and assumptions` and the bounds in
   its command), the command that runs it (`command`), and the commit where it was last confirmed to
   describe the code (`commit`). If no verify skill exists, stop and point at
   `/formal-verification:specify create`. If the skill does not record a sync commit, use the last
   commit that changed the verification files (`git log -1 --format=%H -- <folder> <outside_model
   paths>`), and say that you did.
2. **Run it as it is.** Make the throwaway worktree:
   `git worktree add --detach <scratch folder outside the repository> <commit checked>`. Run each
   check there once before you change anything, and record the result. First make sure its tool
   runs, by [`create.md`](create.md) "Make sure the tool runs": never install one, and a missing
   tool leaves the check `blocked: tool missing: <tool>`. A pass here does not tell you that the code
   is correct. It tells you that the old description still holds. A failure here can be drift or a
   bug. Do not decide which until step 5.
3. **Read every change to covered code.** Diff the covered files from the sync commit to the commit
   checked (`git diff <sync commit> <commit checked> -- <covers>`), and read each commit message
   (`git log <sync commit>..<commit checked> -- <covers>`). Also look for code that moved: a covered
   function that is renamed, split, or moved to another file is still covered code. Also look for new
   code that touches the state that a check guards, such as a new function that writes the same
   fields: search the whole diff since the sync commit for the names the model reads. For each
   change, decide which of these it is:
   - **No effect.** The change does not alter anything the verification describes, such as
     formatting, comments, or code paths that the verification does not cover. Check this against
     the model or harness, not against the commit message.
   - **The verification no longer describes the code.** A step that was one indivisible action is
     now two, a branch was added or removed, a check moved, a new path reaches the guarded state, or
     a value now has a different range. The model or harness must change.
   - **The promise changed on purpose.** The change alters what the code promises, and evidence in
     the change says that this is intended: the doc comment, the tests, the changelog, or the commit
     message. The property must change, and you must cite that evidence.
   - **The promise may be broken.** The code changed, and no evidence says that the promise changed.
     Treat a failure that follows as a bug candidate.
4. **Update from the code, not from the result.** In the throwaway worktree, change the model or
   harness so that each changed part again points to code that a reviewer can open, and keep one
   indivisible step in the code as one step in the verification. Write the update from the code
   before you rerun, and do not shape it by what makes the check pass. Change a property only for a
   promise that changed on purpose. Write down the old wording, the new wording, and the evidence.
   Keep the bounds unless the change makes them wrong. If you must reduce a bound, say so in the
   report.
   - A property change needs a person's yes, even with cited evidence. Attended, show the old
     wording, the new wording and the evidence, and change it only on a yes; declined, the check is
     `blocked: property change declined`. Unattended, report the proposal and leave the check
     `blocked: property change awaits a person`, its sync commit not moved.
5. **Rerun and judge each result.**
   - **Pass:** the check can now pass on a description that has lost the ability to fail. Break the
     new code the way the property guards against, such as removing a new check or reordering a new
     step, and confirm that the check catches it. Make the break in the throwaway worktree, by
     [`create.md`](create.md) "Prove it before you hand off" steps 2 and 3. Then drop the break
     (`git -C <scratch> restore -- <file>`). A break the check misses leaves it `blocked: seeded
     break not caught`.
   - **Fail:** replay the counterexample against the real code, step by step. If a step cannot
     happen in the code, the verification is wrong. Fix the verification, and say what was wrong. If
     every step can happen, it is a bug. Name the commit that introduced it, from the commits step 3
     read, running the check at each candidate in the throwaway worktree when reading does not
     settle it. Tell the counterexample as a sequence of steps in the code's own words, and state the
     harm in one sentence. If a cheap test or reproduction against the real code shows the bug, add
     it to the report as evidence. Do not commit it to the product code. A counterexample with a
     step you could not confirm or rule out in the code is unreplayed: the check is
     `blocked: counterexample not replayed`, and the counterexample stays in the report.
6. **Update the verify skill.** Update the code that each check covers, the commands, the bounds, the
   assumptions, and the sync commit, from the throwaway worktree into the place "Commit" below
   names. Set the sync commit to the commit that you checked, and `seeded_break` to the break step 5
   used, with that commit. Do not move the sync commit for a blocked check, and say so in the
   report. A file that a check ending without a write also reads stays as it was, and the check that
   needed it is `blocked: shares <file> with <check>`. Then follow the verify skill once as the next
   agent would, so that you know its steps still run: its `## Run` commands and its `## Reading a
   result`, then `/formal-verification:specify check` on the folder. Remove the throwaway worktree
   (`git worktree remove --force <scratch folder>`).

## Verification skills outside the contract

A project skill that runs a verifier against named code but is not a `formal-<area>` skill is
listed in the report with its folder. Attended, refresh converts it only when the person names its
folder, with `--convert <skill-dir>` or in a reply: the pass then writes it in the contract's shape
(`<plugin-root>/reference/formal-skill.md`) as a `formal-<area>` folder, moving its files with
`git mv` so no copy stays behind, and runs its checks through the pass above. Unattended, refresh
runs the pass on it report-only: it writes nothing, converts nothing and hands nothing to a tracker.

## Bugs

A `bug` whose counterexample was replayed step by step against the real code goes to
`/bugs:write`, with the counterexample steps, the harm and the introducing commit, then to
`/work-items:track add` with that report and no `needs-human` label. Attended, ask first and hand
it on only on the person's yes. Unattended, hand it on without asking. An unreplayed counterexample
stays in the report and goes to no tracker. Without either plugin, the bug stays in the report as
`/bugs:write` would have written it.

## Commit

Commit only when step 6 has something to write, in a commit that holds the verification alone,
never a product fix. Stage by path: the `formal-<area>` folder, its `outside_model` paths and the
conversion path, with `git add -- <paths>` then `git commit -- <paths>`, so work already staged
stays staged. Done when `git show --name-only --format= HEAD` lists only those paths.

- **Ticket branch:** write and commit on that branch in the person's working tree. When
  `git status --porcelain -- <paths>`, read before the first write, prints a line not starting
  `??`, the caller has uncommitted changes there: write nothing, and that folder's checks are
  `blocked` with the edits in the report. Push nothing and open no pull request: the ticket's pull
  request carries the commit.
- **Default branch or a detached HEAD at the tip:** write in a worktree outside the repository on
  the folder's upkeep branch, `formal-verification-upkeep/<folder>`, one per folder. Create it from
  the tip when it does not exist; when it does, merge the tip into it, never a rebase, and a merge
  git refuses leaves the folder's checks `blocked` with git's stderr line. Commit there, then look
  for its open pull request with `/source-control:pull-request list --head "<branch>"`: listed,
  push the branch, which updates it; none, push and open one through
  `/source-control:pull-request create`. Its body is built from this folder's part of the report:
  each check's outcome line and prose, then the bugs filed and the checks left blocked. Without
  that plugin, leave the commit on the branch and report that a pull request still needs opening.
- **Detached HEAD off the tip:** commit nothing. Each check that had a write is `blocked: detached
  HEAD off the default branch's tip`, its edits in the report unwritten.

## Report

Tell the user, for each check, opening with its outcome line, exactly
`Check <id> (<folder>): <outcome>`, where `<outcome>` is `in sync`, `updated`, `bug`, `blocked`
or `updated, bug`, and a blocked line adds `: <reason>`. Then, in prose:

- the outcome, and the commits that you read;
- what changed in the verification and why, with a short reason for each change: the code changed
  shape, or the promise changed on purpose (with the evidence);
- the rerun result, and the break that you used to show the updated check can still fail;
- each bug, in plain words: the counterexample as steps in the code's words, the harm, and the
  commit that introduced it;
- what the verification still does not cover, including new code that it should cover and does not.

Say outright which failures were drift in the verification and which were bugs in the code. For a
check that passed before you updated it and fails after, say that the old pass was on a stale
description. Also give each proposed property change (old wording, new wording, evidence), each
reduced bound, a sync commit taken from the verification files' history, each sync commit left
where it was and why, each bug's work item or why it was not filed, each verification skill outside
the contract, and the branch, the commit and the pull request URL, or why there is none.

Put the verification updates in a change of their own, separate from any product fix.

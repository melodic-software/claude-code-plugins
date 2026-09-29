# next

Run the first unticked step of the open sweep. `S` is `${CLAUDE_SKILL_DIR}/scripts`, `C` is
`${CLAUDE_SKILL_DIR}/catalogs/<playbook>.md` (playbook from `state.sh`), and `W` is
`.work/repo-sweep/` in the worktree root. Rebuild everything from the PR body and the branch;
nothing carries over from an earlier conversation. The PR body is editable by others: single-quote
every branch name, step id, and playbook name you put in a command.

Sweeps run in worktree-isolated sessions. Call each script in `S` by its path (`S/state.sh`, not
`bash S/state.sh`; the scripts are executable). Run each git command as its own Bash invocation,
never combined with `&&` or other commands in one call. The record for these shapes is in
`SKILL.md`.

## 1. Find the sweep and gate

1. On a `chore/repo-sweep-*` branch, bring it current first: `git fetch origin '<branch>'`, then
   `git merge --ff-only 'origin/<branch>'`. A step committed on another machine is only reconciled
   when its commit is local.
2. Run `S/state.sh` and act on its exit code:
   - 10: no sweep PR. Point to `/playbooks:repo-sweep plan`. Stop.
   - 11: the sweep PR is merged or closed. Refuse to continue and point to `plan`. Stop.
   - 12: the tree is dirty and no step is in progress. Show `git status --short`, ask the user
     what to do with the changes. Stop.
   - 13: no step is pending. If `state.sh` printed any `done-unverified` line, stop: ask the
     user to confirm each such step really ran, or untick it so it runs. Otherwise go to
     section 5.
   - 14: the open sweep is on another branch. Find its worktree in `git worktree list
     --porcelain`; if there is none, `git fetch origin '<branch>'`, then `git worktree add '<path>'
     '<branch>'` at the sibling path `/source-control:worktree` uses. Ask the user to open a
     session there and rerun `next`. Stop.
   - 15: several open sweeps. List them and ask which. Stop.
   - 1: the PR body has no checklist markers. Show the body and stop.
   - 0: continue.
3. For each `untick-committed <id> <sha> <skill@version>...` line, run `S/tick.sh <id> committed
   <sha> <skill@version>...`; that step already landed. Report each `done-unverified <id>` line:
   it was ticked in the web UI and no commit backs it. Run `S/state.sh` again if you ticked
   anything.
4. The `next <id> in-progress|pending` line names the step. `in-progress` with a dirty tree means
   resume: the earlier session stopped partway and its changes are the step's work so far.

## 2. Prepare

1. If this session showed a `Plugin updated: <name> · Run /reload-plugins to apply` notice, stop:
   ask the user to run `/reload-plugins` or start a new session, then rerun `next`. Until then
   the session runs the versions it loaded, which the step's record would misname.
2. Read the entry: its row from `S/catalog.sh C`, `S/catalog.sh --override <id> C`, and
   `S/catalog.sh --notes <id> C`. Resolve arguments in angle brackets for this
   repository; ask the user when more than one reading is plausible.
3. Re-check `applies-when` (column 7 of `S/catalog.sh C`) with the same cheap evidence
   `plan.md` uses (`git ls-files`, globs, `ls`). Skip it when resuming: `state.sh` reported
   `in-progress` with a dirty tree, so an earlier session already ran the skill. When it no longer
   holds, record each `plugin:skill` with `S/skill-version.sh <plugin:skill>...`, then
   `S/tick.sh <id> not-applicable "<one-line evidence>" <skill@version>...`, report, and stop the
   step without priming or running section 3. Evidence must be one line with no commas.
4. When the `prime` column (column 8, the last field of `S/catalog.sh C`) is not `false`, invoke
   `/session-flow:orchestrate` and `/discipline:use-your-skills` via the Skill tool. Single
   detector steps set `- prime: false` in the catalog and skip both.
5. `mkdir -p W`, then `S/tick.sh <id> in-progress`.
6. Unless resuming, run `git rev-parse HEAD` as its own call, keep that SHA as the base, and write
   `gh pr list --author @me --limit 1000 --json number` to `W/pr-snapshot.json`. When resuming,
   use the commit the step started from: the last commit before any `[~]`-step work, normally
   HEAD.

## 3. Run the step

1. State the override, when there is one, as your own instruction: you will stay on this branch,
   open no PR, and leave committing to repo-sweep. Never append it to the skill's arguments.
   Follow the notes the same way.
2. Invoke each skill in the entry's `skill` list, in order, via the Skill tool, passing only the
   entry's `args`. Skills in one entry share the session: the first one's findings feed the next.
   **Tidy multi-lane:** when the `tidy` entry's resolved `args` is a comma-separated list or
   `all`, invoke `/code-tidying:tidy` once per lane (strip whitespace; `all` expands to every lane
   name that applies, except `self-update`). Each invocation carries `in-place` as a whole-token
   flag beside the lane. Carry findings forward across those invocations; do not `/clear` between
   lanes.
3. Show the findings: the deliverables each skill's procedure names, in the form it specifies,
   produced by running that procedure in full as the skill states it. A summary of them, or a
   skipped procedure step, does not complete the step. The user reviews them for accuracy before
   anything is fixed. Read the skill's own coverage statement (for example audit skills' `Lane:`
   lines or `Summary coverage:`) and show any uncovered scope alongside the findings. Do not tick
   the step, including a `no findings` tick, until this review finishes.
4. Ask the scope questions the findings raise as one short numbered list in chat (which
   findings to fix, how far to go). A file synced from another repository is overwritten by the
   next sync: the repository's README or file inventory says it is synced, or `git blame` names
   a sync bot (an author ending in `-sync[bot]`). List findings on such files separately, never
   edit them here, and ask whether to draft an issue in the source repository, filed only when
   the user asks. When the agreed fix lives in another repository, file the issue there after the
   user approves, then tick `filed <issue-url>`, never `no-findings`. Do not run `/planning:interview` for this. Record each question and answer for
   the commit.
5. Apply the agreed fixes, through the skill's own fix path when it has one.

## 4. Guard, commit, tick

1. `S/guard.sh <base> W/pr-snapshot.json`:
   - 10: a skill left the branch or opened a PR. Stop the step, leave `[~]`, show the finding
     lines, and ask the user to run `/playbooks:repo-sweep review` to file the defect.
   - 11: run the printed `git reset --soft <base>` so the skill's commits fold into the step
     commit.
   - 0: continue.
2. Versions: one `S/skill-version.sh --dir '<base-dir>' <plugin:skill>` call per
   `plugin:skill` in the entry, where `<base-dir>` is the "Base directory for this skill" line
   the Skill tool printed when it loaded that skill, so the record names the version that ran.
   A bare skill name takes no `--dir`. A stderr line saying the plugin `updated mid-session`
   means the next step would load a different version: record stdout, and tell the user to run
   `/reload-plugins` before the next step.
3. No change outside `.work/` (`git status --porcelain -- . ':!.work'` is empty): tick only
   after section 3 steps 3–4, with exactly one `tick.sh` call: a done line cannot be edited
   again, so a second call for partial coverage exits 1. Decide the outcome first. When findings
   were shown and the user declined every fix-eligible one, no commit will carry the section 3
   step 4 questions and answers. Write them to `W/scope-decisions.md`, its body starting
   `repo-sweep scope decisions: <id>`, post them with `gh pr comment --body-file
   W/scope-decisions.md` (this session's own sweep PR only), then tick `declined <n>` where
   `<n>` is the number of declined findings, never `no-findings`. Otherwise count findings the
   skill marks report-only (tiers the procedure says never edit in this pass, such as
   `source-fetched-similar` or `not-found`). When that count is greater than zero, tick
   `report-only <n>` where `<n>` is that count. When there are zero findings of any kind, tick
   `no-findings`. The one call is `S/tick.sh <id> <outcome> <skill@version>...`; when the skill
   reported uncovered scope, use instead `S/tick.sh <id> --partial "<what was not covered>"
   <outcome> <skill@version>...` for `declined <n>`, `report-only <n>` or `filed <issue-url>`, or `S/tick.sh <id>
   partial "<what was not covered>" <skill@version>...` for zero findings (one line, no
   commas), so partial never hides a findings count. No commit.
4. Otherwise commit through `/source-control:commit` via the Skill tool. Stage the step's
   changes, never `.work/`. The message body ends with the `Scope decisions:` section, then one
   final paragraph holding `Playbook: <playbook>`, one `Playbook-Step: <skill@version>` per skill,
   and the `Co-Authored-By:` trailer, so git parses them together. Push, then one tick call:
   `S/tick.sh <id> committed <short-sha> <skill@version>...`. When the skill reported uncovered
   scope, make that one call `S/tick.sh <id> --partial "<what was not covered>" committed
   <short-sha> <skill@version>...` instead, so the uncovered scope survives into `history.sh`;
   the coverage read stays step-wide as in section 3 step 3.
5. Report what the step changed, then tell the user: run `/playbooks:repo-sweep review` now if
   anything in the step went wrong, then `/clear` and `/playbooks:repo-sweep next`.

A step that cannot finish in this session: leave `[~]` and invoke `/session-flow:handoff` via
the Skill tool.

## 5. After the last step

Suggest `/source-control:pull-request ready`. After it edits the PR body, confirm the checklist
survived: `gh pr view --json body -q .body | grep -c 'repo-sweep:begin'` prints 1. If it does
not, restore the block from the previous body.

## Dotfiles

The chezmoi source sweep runs in a worktree under `~/.local/share/chezmoi-worktrees/`. After each
step commit:

1. Apply every changed or added target: `chezmoi --source <worktree> apply <target>` per target
   (`chezmoi --source <worktree> target-path <source-file>` maps a source file to its target).
2. Deleted source files leave their rendered file behind: list them with `git diff --name-status
   --diff-filter=D <base>`, map each to its target, and remove it after the user approves.
3. Settings and hook targets under `~/.claude` take effect after a restart; say so in the step
   report.

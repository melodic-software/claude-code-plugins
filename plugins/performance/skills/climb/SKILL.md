---
description: "Keep-or-revert loop on a frozen harness: one hypothesis and one commit per attempt, both arms re-measured every time, kept by a rule written before the first attempt, logged outside the tree, in its own worktree and branch. Use when: 'keep trying changes until this counter drops', 'hill-climb this benchmark', 'iterate on this until the target is met', 'run an optimization loop'. After /performance:snapshot baseline, before /performance:verify. Skip when: the score comes from an eval set for an LLM app (`/claude-api hillclimb`); one before-and-after comparison (`/performance:snapshot`)."
user-invocable: true
argument-hint: "[<goal-slug>]"
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Keep or revert one measured change at a time until the goal is met
---

**Arguments.** `[<goal-slug>]`. e.g. /performance:climb site-build-template-parses

## Purpose

Answers **"which of these changes actually moved the number, and how far can it go?"**

Measure one change at a time: hypothesis, change, commit, measure both arms, apply the rule, keep
or revert, log, until the goal is met. Keep every judgment out of reach of the attempt being
judged: the rule is written first, the harness is frozen, and the baseline is re-measured beside
each attempt.

Read [`${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md`](${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md)
before the first attempt.

## Inputs, or stop

1. **A goal from `/performance:goal`** with its floor, its Realistic target and `min_attempts`. A
   goal without `min_attempts` goes back to `/performance:goal`; never pick one here, since goal is
   human-gated.
2. **A harness `/performance:snapshot` froze**: the command, the commit it was frozen at, and its
   discrimination result. Send the run back to `/performance:snapshot baseline` when no harness is
   frozen, or when its output carries neither tally. Each harness run must print three numbers: the
   goal's counter, a tally of failures and a tally of finished work units.
3. **A clean checkout.** `git status --porcelain` in your checkout prints nothing. Refuse
   otherwise and name the files: the loop starts from a commit, and uncommitted work is not in it.
4. **Optional: a holdout harness `/performance:snapshot` froze**, a second command that prints the
   same three numbers on inputs the main harness does not use. It needs its own `Frozen:` line in
   the baseline report with `discriminate: exit 0`, worded like item 2; send the run back to
   `/performance:snapshot baseline` when the line is missing. **Absent means off**: the run behaves
   exactly as it does without this item, and nothing below that mentions the holdout applies.

## Set up, before the first attempt

1. **Memory slice.** Use `<memory_dir>/<topic-slug>/climb/<goal-slug>/` in your checkout (default
   `<memory_dir>` is `.work/`), by absolute path: the loop runs in another worktree, and the log
   must outlive it. Done when the directory exists.
2. **Keep rule.** Write `keep-rule.json` there with exactly three keys: `counter` (the goal's
   counter, by name), `direction` (`lower` or `higher`) and `gain_floor` (the change in the counter
   that counts as a gain; the host's measured noise for a duration, `0` for a deterministic count).
   Show it to the person when one is present. **Never edit it during the run**: once an attempt
   has a number, any change to the file would tailor the rule to that number.
3. **Two worktrees, outside your checkout or in a directory its `.gitignore` ignores.** Start both
   at your checkout's `HEAD`:
   - climb's own: `git worktree add -b climb/<goal-slug> <climb-path> <start-sha>`. A branch with
     that name already exists: stop and ask, since it may hold an earlier run.
   - the baseline arm: `git worktree add --detach <baseline-path> <start-sha>`. It always sits at
     the last kept commit.

   Every attempt happens in `<climb-path>`. Nothing in this skill edits, commits in or resets your
   checkout.
4. **Starting measurement.** Run the harness once in each worktree. The counters agree, the error
   counts are zero and the work counts match, or the harness is not stable enough to climb on:
   stop and say which number differed.
5. **Holdout, only when item 4 is given.** Write `holdout.json` in the slice, holding the
   holdout's `Frozen:` command and sha; like `keep-rule.json` it is never edited during the run.
   It is not a key of `keep-rule.json`, which `decide` accepts only with its three keys. Then run
   the holdout once in each worktree, by absolute path, as step 4 does: the counters agree, the error counts are zero
   and the work counts match, or stop and say which number differed. This is a stability check
   only; its number is never compared at the end. Run the holdout nowhere else until the run ends.

## One attempt

1. **Read the log**: `python3 "${CLAUDE_PLUGIN_ROOT}/skills/climb/scripts/climb_log.py" show --log <slice>/log.tsv`.
   Do not retry a mechanism already reverted unless the new attempt says what differs.
2. **State one hypothesis that names a mechanism**: what the code does now, why that costs the
   counter, and what the change removes. "Templates are parsed once per page; parsing once per
   build removes N-1 parses" qualifies. "The renderer does too much" does not: it names no code
   path and predicts no number.
3. **Make one change** in `<climb-path>` that tests that hypothesis and nothing else. Never edit
   the harness files, the holdout harness included. Never read holdout output while forming a
   hypothesis; holdout numbers never go into `log.tsv`, so `show` carries none.
4. **Commit it** on `climb/<goal-slug>`, staging the changed files by name.
5. **Run the project's tests** in `<climb-path>`. Record `pass` or `fail`.
6. **Measure both arms in one sitting.** Run the snapshot harness `ab.sh` with `--a` running the
   harness in `<baseline-path>` and `--b` running it in `<climb-path>`, at the goal's iterations and
   percentiles. `ab.sh` discards each arm's output, so also run the harness once in each worktree
   and read its counter, error count and work count. Never compare against a number stored from an
   earlier attempt; the baseline arm is re-measured every time. Never run the holdout harness here.
7. **Decide**: `python3 "${CLAUDE_PLUGIN_ROOT}/skills/climb/scripts/climb_log.py" decide --rule <slice>/keep-rule.json --before <baseline counter> --after <attempt counter>`.
   Settle the verdict in this order, stopping at the first line that applies:
   1. Tests failed, the error count rose, or the work count differs from the baseline's:
      `reverted`, whatever `decide` prints. Finishing fewer work units is not a speedup.
   2. `decide` prints `kept`: `kept`.
   3. `decide` prints `reverted`, the counter is no worse than the baseline's, and
      `git diff --numstat <last kept sha> <attempt-sha>` shows lines removed and none added:
      `kept`, noted `simplification`. Deleting code without losing ground on the counter is a
      result in its own right.
   4. Otherwise: `reverted`.
8. **Keep or revert.**
   - Kept: move the baseline arm to the attempt, `git -C <baseline-path> checkout --detach <attempt-sha>`.
   - Reverted: in `<climb-path>`, `git reset --keep <last kept sha>`. That moves only climb's own
     branch, and it refuses rather than overwrite uncommitted edits. If it refuses, stop and report
     the files; never use another reset form to force it.
9. **Log the row**: `python3 "${CLAUDE_PLUGIN_ROOT}/skills/climb/scripts/climb_log.py" append --log <slice>/log.tsv`.
   Every row passes all nine flags. The outcome goes in `--verdict` (`kept` or `reverted`) and
   `--tests` (`pass` or `fail`); the measured numbers in `--before`, `--after` and `--delta`; the
   text in `--id`, `--hypothesis`, `--change` and `--note`. When the verdict is `reverted`, put the
   dropped SHA in `--note`; `git show` on that SHA still displays the attempt.

- **Pointer**: for what `--keep` refuses and what it moves, see
  [git-reset `--keep`](https://git-scm.com/docs/git-reset#Documentation/git-reset.txt---keep).
  **As of**: 2026-10-04. **Recheck trigger**: the git-reset page changes the `--keep` description.

## When the run ends

| Logged attempts | Last kept value | Budget | Untried mechanism | Action |
|---|---|---|---|---|
| any | any | spent | any | finish; report the target as not met when it is short |
| at or above `min_attempts` | meets the Realistic target | left or not set | any | finish |
| any | short of the target, or `min_attempts` not reached | left or not set | at least one | next attempt |
| any | short of the target, or `min_attempts` not reached | left or not set | none | finish; report `Next idea: none left` and which condition was not reached |

A budget is optional. Without one, the last row is what ends a run that never reaches its target.

`min_attempts` is a floor on evidence: the attempts after the first kept one show whether the
counter has more room. The goal, the keep rule and the budget stay as written until the run ends.

## Choosing the next hypothesis

- **Smaller first.** Between two hypotheses expected to move the counter by about the same amount,
  attempt the one with the smaller change first; the number never justifies extra code on its own.

- **From the log.** Group the logged rows by the mechanism each one named. Prefer a mechanism no
  row has tried yet over a variant of a reverted one.
- **After three reverts in a row**, run `/performance:target` against `<climb-path>` when it is
  among the available skills, and take the next hypothesis from its ranking; without it, profile
  the harness run once and pick the largest cost no row has touched.
- **Report what each gain cost.** Each kept line in the report carries its `git diff --stat`
  totals, so the reviewer can weigh a small gain against a large change.

## Unattended runs

The skill starts no `/goal` and sets no loop. For a run nobody watches, draft its stop condition
first with `/planning:draft-goal-condition` when that skill is among the available skills,
naming the goal's target, `min_attempts` and the budget; without it, write the condition from
those same three items. The person starts the run with that condition.

## Finish

0. **Holdout, only when item 4 is given.** Both worktrees sit at the last kept sha. When it equals
   the start sha, skip the measurement and report `Holdout:   not run (nothing kept)`. Otherwise
   run `git -C <baseline-path> checkout --detach <start-sha>`, then run the holdout once in each
   worktree, by absolute path, and read its counter, error count and work count; no `ab.sh` run
   is needed. Call `decide --rule <slice>/keep-rule.json --before <holdout counter on the start sha>
   --after <holdout counter on the last kept sha>`: `kept` reports `held`, `reverted` reports
   `did not hold`. As in step 7.1, a rose error count or a differing work count reports
   `did not hold` whatever `decide` prints. A run whose kept attempts are all simplifications
   (step 7.3) reports whatever `decide` prints; a `did not hold` there says only that the holdout
   showed no gain. The holdout informs and never reverts: a gain that did not hold is still the
   climb's result. Do this before step 1 removes the worktrees.
1. Remove both worktrees with `git worktree remove <path>`. The branch `climb/<goal-slug>` stays
   and holds the kept commits in commit order. `git worktree remove` refuses a worktree with
   modified tracked files or untracked files that `.gitignore` does not cover; ignored files do not
   block it. When it refuses, leave that worktree in place, name its path and the files
   `git status --porcelain` lists in the report, and let the person clean it. Never pass `--force`.
2. Report:

```text
Branch:    climb/<goal-slug>
Log:       <absolute path to log.tsv>
Counter:   <counter>, <direction>; Realistic target <Realistic target>
Moved:     <start value> -> <last kept value> (<percent change>)
Evidence:  min_attempts <n>; logged <n>: kept <k>, reverted <r>
Holdout:   <held|did not hold>; <holdout counter on start sha> -> <holdout counter on last kept sha>, or "not run (nothing kept)"   (only when a holdout was given; with errors or work counts that differ, name them)
Next idea: <the untried hypothesis most likely to move the counter, or "none left">
Changes, oldest first, one line each:
  <sha> <change> (<files> files, +<added> -<removed>)
```

- **Pointer**: for which worktrees `remove` accepts, see
  [git-worktree `remove`](https://git-scm.com/docs/git-worktree#Documentation/git-worktree.txt-remove).
  **As of**: 2026-10-04 (ignored-only output was also checked by hand: removal succeeds). **Recheck
  trigger**: that section changes what counts as a clean worktree.

## Boundary

- **Does not set the goal or the rule's counter.** `/performance:goal` does, with a person.
- **Does not freeze the harness.** `/performance:snapshot` does.
- **Does not decide the result is real.** `/performance:verify` re-derives it in a fresh context.
- **Does not climb an eval score.** For an LLM app scored against an eval set, the person types
  `/claude-api hillclimb`; this skill never starts it.

- **Pointer**: for the `/claude-api` subcommands, see
  <https://code.claude.com/docs/en/skills#work-on-claude-api-projects>. **As of**: 2026-10-04.
  **Recheck trigger**: that section drops or renames `hillclimb`.

## Next

`/performance:verify` on the branch `climb/<goal-slug>`, with the log path.

## Gotchas

- **The rule file judges every gain.** If an attempt looks good and `decide` says `reverted`, the
  attempt is reverted unless it is a pure deletion (step 7, line 3). Change the goal through
  `/performance:goal` before the next run, never during this one.
- **A counter that stops moving can mean the harness stopped running the code.** Check the work
  count before concluding a mechanism had no effect.
- **The baseline worktree is detached on purpose.** It follows kept commits only; a branch there
  would collide with `climb/<goal-slug>`.
- **Run the harness, and the holdout harness, by absolute path in both worktrees.** A relative
  path run from the wrong directory measures the same tree twice.

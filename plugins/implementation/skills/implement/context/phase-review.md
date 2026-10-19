# Phase-boundary review

A plan phase tagged `Review: <concern>` gets that review at its boundary, before the acceptance
verdict and the commit. SKILL.md Step 4 holds the tag-to-mode table; this file holds the rest.

## Inputs

- **Tags.** Each `Review:` line under the phase header names one concern. Run one gate call per
  tag in the table, in the order the plan lists them. A value outside the table dispatches nothing;
  say so in the boundary report.
- **Base.** `--base <sha>`: the previous phase-boundary commit, or for the first phase the commit
  HEAD was on when Step 1 passed. The change set is everything since that commit, uncommitted
  edits included.
- **Quality bar.** `--quality-bar <prototype|internal|production>` copied from the plan's
  `Quality bar:` line. With no such line, pass nothing; the gate rates as production and says so.
- **Report only.** `--report-only` always: the gate writes no findings file and asks nothing, and
  this skill keeps the result.
- **No rationale.** Pass no plan reasoning, conversation or account of the change. The gate's
  reviewer runs in fresh context on the diff, the tag and the quality-bar line alone.

## Sequence

1. **Review.** Run every tagged call against the same head, and record that head's SHA, or `dirty`
   when the reviewed tree was uncommitted.
2. **Fix.** Fix each CRITICAL and IMPORTANT finding with an edit inside the phase's own files.
   A finding whose fix needs a file outside the phase is a divergence (Step 3), not a fix.
   SUGGESTION findings are reported, not fixed. With no CRITICAL or IMPORTANT finding, skip to
   step 4.
3. **Re-review, once.** Rerun only the tags whose findings were fixed. When the reviewed head was a
   commit, pass that SHA as `--base`, so the diff is the fixed hunks alone; when it was `dirty`,
   keep the phase base and judge only findings on the fixed hunks. There is no second re-review.
4. **Verdict.** Step 4 item 1 runs last, on the fixed tree.

## A repeated CRITICAL

A re-review that rates the same finding (same file and defect) CRITICAL again stops the loop:

- Append a `human-decision` entry marked blocking to `DEVIATIONS.md` in the memory slice: the tag,
  the finding with its `file:line`, the fix that was tried, and the head SHA.
- Escalate once. Interactive: put the finding to the user with the options (fix another way,
  accept the risk, replan). Unattended: the entry is the escalation; leave the phase unmarked and
  park the run, which is blocked on a call only a person can make.
- Never fix and re-review a third time, and never mark the phase `[DONE]` over it.

An IMPORTANT finding that survives the re-review goes into the boundary report and, when the run
keeps the log, a `discovery` entry; the phase continues.

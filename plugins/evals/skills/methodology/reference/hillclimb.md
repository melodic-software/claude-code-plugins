# Hillclimbing against an eval suite

This file points at the bundled `/claude-api hillclimb` workflow and states only what this
repository adds to it. Each upstream step is named by a link to its section; read the step there.
No step is restated here.

## Where the workflow lives

- **Pointer**: for the `/claude-api` subcommands, `build-eval` and `hillclimb` among them, see
  <https://code.claude.com/docs/en/skills#work-on-claude-api-projects>.
- **Pointer**: for the hillclimb guide itself, see
  [`eval-hillclimb.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md)
  at the pinned commit; for the guide that builds the eval first, see
  [`build-eval.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md).
- Correlate with <https://claude.dev/blog/automating-eval-design-and-hillclimbing#claude-api-hillclimb>.
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes a file under
  `skills/claude-api/shared/evals/`, or a Claude Code release note changes the bundled
  `claude-api` skill's eval guides. Then re-read each linked section and move the pin.

## Who starts it

Skills in this plugin never start `hillclimb` or `build-eval` themselves. They tell the user to
type `/claude-api hillclimb` (or `/claude-api build-eval`) and stop, because no doc says the model
may start a `/claude-api` subcommand workflow on its own. The user's own command is also the
approval to change the target.

- **Pointer**: for how a subcommand workflow is started, see
  <https://code.claude.com/docs/en/skills#work-on-claude-api-projects>.
- **As of**: 2026-10-01
- **Recheck trigger**: a docs page states whether the model may start a `/claude-api` subcommand
  workflow.

## Whether it can drive a `claude plugin eval` suite

Yes, through Step 0.5, with no adapter. This plugin ships no wrapper skill; this file stays a
pointer.

- **Test**: a user-run hillclimb took this plugin's own suite (`claude plugin eval` with
  `--runs 2 --keep-temp`) as its runnable eval and stopped after Step 0.5, on Claude Code 2.1.287,
  2026-10-01. Baseline, noise floor and the mechanism check all came from `aggregate-result.json`,
  `scripts/noise-report.py` and the kept traces.
- **Past Step 0.5**: this plugin ships no converter from `aggregate-result.json` to the layout the
  later steps read. A cost-goal iteration (2026-10-02) ran without one and produced no report
  page. For that layout, see
  [`SCHEMA.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/report/SCHEMA.md)
  at the pinned commit.
- **Small suites**: report this plugin's suite results as directional. For how hillclimb treats a
  small suite, see
  [eval-hillclimb.md Step 3](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-3-set-up-state-split-the-data-and-take-a-baseline).
- **Recheck trigger**: a Claude Code release changes the `plugin eval` result format, or the
  hillclimb guide changes the inputs its Step 0.5 reads.

## Step map

Each row names an upstream step and states this repository's fact for it.

| Upstream step | This repository |
|---|---|
| [Step 0](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-0-confirm-theres-a-runnable-eval) | For a Claude API app with no eval, the user types `/claude-api build-eval` first. For a skill or plugin repository, the candidate eval is `claude plugin eval` over the plugin's suite, run through `/evals:plugin-eval`; whether hillclimb accepts it is the open question above |
| [Step 0.5](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-05-prove-the-eval-can-be-climbed) | Before round 1, check the suite's resolution against [eval-audit section 5](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md#5-can-it-detect-the-change-youre-after). A plugin case that scores 1.00 without the plugin leaves nothing to climb |
| [Step 1](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-1-agree-on-the-goal-what-to-change-and-how-its-wired-in) | For a skill, choose its `SKILL.md` or reference files as the target and choose real skill discovery as the wiring, so the climb exercises the skill the way `claude plugin eval` loads it. For a cost climb, see [Cost as the goal](#cost-as-the-goal) |
| [Step 2](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-2-agree-on-a-stopping-condition-and-a-budget-if-cost-matters) | One `claude plugin eval` invocation is capped by this plugin's `max_cost_usd` setting; set the hillclimb budget with that ceiling in view |
| [Get the plan approved](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#get-the-plan-approved) | The user approves. No skill here answers for them |
| [Step 3](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-3-set-up-state-split-the-data-and-take-a-baseline) | This repository's split default and its source conflict are recorded in [local-decisions.md](local-decisions.md#split-policy) |
| [Step 4](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-4-the-loop) | Run the loop in a disposable clone of the repository, never in a shared checkout or worktree |
| [Step 4.5](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-45-when-the-loop-stalls-categorize-before-grinding) | A fix carried back into a skill states the general cause in the author's own words; it never copies case text, and never draws on cases held back for testing |
| [Step 5](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-5-report-and-hand-back) | Confirm the kept change with a fresh `/evals:plugin-eval run` at the CLI's default run count, and read its delta there |
| [Failure modes to avoid](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#failure-modes-to-avoid) | Read before round 1. This repository adds none |

## Building the eval first

For a Claude API app with no eval, the user types `/claude-api build-eval` before hillclimb. Its input review is
[Get the inputs approved](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#get-the-inputs-approved);
its steps start at
[Step 0](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#step-0-understand-whats-being-evaluated),
[Step 1](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#step-1-find-or-build-the-input-set)
and
[Step 2](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#step-2-decide-how-to-grade).
For a skill or plugin repository, `/evals:design` scaffolds the suite and `/evals:plugin-eval` runs
it.

## Cost as the goal

This repository adds no cost tool. To climb on cost, answer hillclimb's
[Step 1](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-1-agree-on-the-goal-what-to-change-and-how-its-wired-in)
goal question with cost, and read `cost-hillclimb.md`:
[the search order](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/cost-hillclimb.md#the-search-order),
[adoption gates](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/cost-hillclimb.md#adoption-gates---register-before-round-1),
[measurement discipline](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/cost-hillclimb.md#measurement-discipline)
and
[stopping rules](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/cost-hillclimb.md#stopping-rules).
`/evals:plugin-eval` keeps each run's cost next to its score.

- Correlate with <https://claude.dev/blog/automating-eval-design-and-hillclimbing#hillclimbing-for-cost-reduction>.
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes `cost-hillclimb.md`, or a docs page
  starts covering the hillclimb cost goal; then the pointer moves there.

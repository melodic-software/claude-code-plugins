---
name: formal-ci-lanes-carry-forward
description: "TLA+ model of the `ci-lanes` commit status on one pull request head: full runs of PR Require Checks mark it pending and record the lanes verdict, and a contract-only run (a label flip or body edit) yields to a full run in flight or carries the recorded success forward. Use when a change touches .github/workflows/pr-require-checks.yml's mark-lanes job, the ci-status job's needs or its Aggregate lane results inputs, or repins the ci-workflows report-ci-status composite, or to ask whether a label flip can pass CI Status on an older verdict while a full run is in flight."
disable-model-invocation: true
---

# Formal check: the ci-lanes carry-forward

## Property

Each rule is an INVARIANT in `model/CarryForward.tla`. `WF` is
`.github/workflows/pr-require-checks.yml`; `REPORT` is
`.github/actions/pr-require-checks/report-ci-status/action.yml`, `RUN` is
`.github/actions/pr-require-checks/aggregate-results/run.sh` and `ACTION` its `action.yml`, in
`melodic-software/ci-workflows` at the commit `WF` pins on the ci-status job's Aggregate lane
results step. `REPORT` runs `aggregate-results` at that same commit.

| Rule | Plain sentence | Source |
|---|---|---|
| `NoStaleCarry` | A contract-only run that passes carries no success a full run in flight is about to replace: every full-run attempt in flight when it passes wrote that success, or started after the run's last listing of the runs. | `WF`, the mark-lanes comment: "A FULL RUN MARKS ITS SHA IN FLIGHT AT ONCE. A contract-only run on this SHA reads the newest bot-written `ci-lanes` status once and passes only on `success`, so this `pending` makes it fail at once instead of carrying forward a verdict this run is about to replace"; `RUN`, the yield block: "This closes the gap `record-pending` alone leaves: a full run that is queued, or whose first job has not yet written its `pending` marker, would otherwise let this run carry an older `success` forward across it." |
| `HeldPassIsNewer` | A run that held for full runs passes only on a success created after each of them started. | `ACTION`, `yield-wait-seconds`: "passes only on a `success` created at or after their latest start. An older `success` does not pass" |
| `PassCarriesSuccess` | A contract-only run passes only on a success whose writer it verified. | `RUN` header: "A `success` passes only when its writer run is a full run of this same workflow on this SHA whose aggregate step succeeded" |

How the rules read the model's states:

- A full run is in flight from the event that creates it (queued) until it completes or is
  cancelled, as GitHub's run listing reports it. Each re-run is a new attempt with a new start.
- `NoStaleCarry` is judged at the step where the contract-only run decides to pass, over the
  full-run attempts in flight at that step. An attempt that started after the run's last listing
  is exempt: the run cannot see it. "Known results" gives that window's path.

`TypeOK` checks the variables' types. `NoStaleCarryAtPass`, the same rule without the exemption,
is defined in the model and checked in no shipped cfg.

## Harm

A label flip or body edit turns `CI Status` green on a verdict an in-flight full run is about to
replace, so a pull request can merge past lanes that are red.

## Tool and why

TLA+ with TLC, read through `/formal-verification:chart`. The question is whether GitHub events,
full runs and a contract-only run's API calls can interleave into a bad order; a model checker
tries every order of a small model, and these races sit between a run listing, a status read and a
status write that no test sequences. `formal-claim-protocol` records the same tool for a like
question.

An agent generated this skill by following the `specify` skill's files in this repository, not
through an installed-plugin invocation of `/formal-verification:specify`.

## Bounds and assumptions

- One head SHA; two full runs, `run1` and `run2`; `run1` may be re-run once (`MaxAttempts = 2`,
  `Rerunnable = {"run1"}`), `run2` runs once; one contract-only run, which may start at any point
  (a re-run of it is a later start).
- Every full run is a same-repository `pull_request` run, so mark-lanes runs and tries its marker
  (`WF`, the mark-lanes `if:`), and its jobs read `full` to the yield listing. With `MarkMayFail`
  the marker's three tries may all fail, and ci-status then records a failure.
- A full run's lanes are one verdict, success or failure, which ci-status records after mark-lanes
  (`needs`). A re-run either re-runs every job (mark-lanes marks again) or only failed jobs (a
  successful mark-lanes is kept and writes nothing).
- Any full run may be cancelled at any step, and a completed `run1` may be re-run. Both full runs
  may be in flight at once, which the per-pull-request concurrency group mostly prevents: the
  model allows more orders than GitHub does.
- Each GitHub call is one step, with two exceptions: the writer check of a success
  (`verify_carried_writer`, `verify_writer_step`, `verify_no_newer_verdict`), whose jobs reads are
  one step, and the hold's poll, whose exit is one step. The run listing and the status read are
  separate steps.
- The listing shows a run the moment it is created. Every read succeeds: a failed read fails the
  contract-only run closed, which cannot make it pass. Only the newest status is kept, since every
  reader takes the newest by id.
- Time is a counter: every start and every status write takes a later tick. The code compares
  second-resolution timestamps (`writer_attempt_wrote`: `.run_started_at <= $since`); the model
  assumes a re-run never starts in the same second as its earlier attempt's write, which needs that
  attempt to finish its ci-status job and be re-run inside one second.
- The ceilings (the 30 s writer wait and the 600 s `yield-wait-seconds`) are one event that can
  happen at any step of the yield loop.
- Full runs stop moving once the contract-only run has its verdict: no rule reads anything after.
- The cfgs use `VIEW View`, which replaces each tick by its rank among the state's ticks; ticks are
  only compared, so states with the same order behave alike. Under it TLC's distinct-state count
  depends on exploration order; the chart command runs one worker, so its count is stable. The view
  does not decide the verdicts: without `VIEW`, `Yield.cfg` holds every rule at
  726f82db25b4 (21,746,774 states, the chart command with one worker, 3 min 34 s). Rerun without
  it after any change to `View` or to what holds a tick.
- The seeded break in `sync.yaml` was run against this model: with `yield-to-full-run: 'false'`
  (`Yield = FALSE`), `NoStaleCarry` breaks after 5,056 distinct states in `Yield.cfg` and 7,972 in
  `YieldNoHold.cfg` (`caught: true`).

## Not covered

- Fork pull requests (they write no status), `merge_group`, `workflow_dispatch` and schedule runs:
  they write `ci-lanes` on a SHA no contract-only run reads (`WF`, the comment on `merge_group`).
- A forged status: another workflow, a person or a token writing `ci-lanes`, which the creator,
  workflow and run checks in `read_newest_entry` and `verify_carried_writer` guard.
- Two contract-only runs on one SHA, the full run's wait for in-flight siblings before it re-runs
  them (`rerun-wait-seconds`), the jobs-shape reads of a run whose jobs are not listed yet, alias
  jobs, rate limits, and `carry-forward-wait-seconds` above `0`.
- `.github/scripts/pr-unblock/fix-ci-dispatch.mjs`, which reads `ci-lanes` to decide whether to
  dispatch a fix and gates no merge.
- Which of two `CI Status` check runs on one SHA GitHub's required check reads; the model checks
  the contract-only run's own verdict.
- A re-run of `run2`, and `MarkMayFail` with a hold: with both runs re-runnable and the marker
  allowed to fail, TLC under `VIEW` had not finished at 15 million states after three minutes on 8
  workers, so neither is a shipped check.

## Run

One command per cfg; `Yield.cfg` takes about three minutes, `YieldNoHold.cfg` under a minute:

```text
/formal-verification:chart .claude/skills/formal-ci-lanes-carry-forward/model/CarryForward.tla --config .claude/skills/formal-ci-lanes-carry-forward/model/Yield.cfg --view .claude/skills/formal-ci-lanes-carry-forward/model/view.mjs --rerun-states 6000000
/formal-verification:chart .claude/skills/formal-ci-lanes-carry-forward/model/CarryForward.tla --config .claude/skills/formal-ci-lanes-carry-forward/model/YieldNoHold.cfg --view .claude/skills/formal-ci-lanes-carry-forward/model/view.mjs --rerun-states 6000000
```

`Yield.cfg` is the setting on an open pull request's label flip: `yield-to-full-run: 'true'`, which
`REPORT` fixes (`Yield`), and the `yield-wait-seconds` of 600 `WF` passes (`Hold`).
`YieldNoHold.cfg` is a `yield-wait-seconds` of `0` (a draft, or a contract-only run whose job,
contract or draft step already failed), with the marker allowed to fail. `--rerun-states` must
cover the whole space (4,788,560 and 880,975 states): after a rule breaks, the command rechecks the others
under that bound, and a smaller bound leaves them not checked.

Pass a new `--out` folder each run.

## Reading a result

Replay each counterexample step by step against the code, one call per action. `Start`, `Rerun`,
`Cancel` and `Complete` are GitHub events on a full run; `Mark` and `MarkFails` are mark-lanes;
`Aggregate` and `StepEnds` are the full run's Aggregate lane results step. `CList`, `CRead`,
`CVerify`, `CDecide`, `CHoldEnds` and `CTimeout` are the contract-only run's yield loop in `RUN`;
`SRead`, `SList` and `SReRead` its single read when `Yield` is `FALSE`. Each action's comment in
the model cites its lines. If a bug does not occur, think that the model is wrong until you show
that it is not. A path that reproduces is a bug: write it up with `/bugs:write`.

Known results at the sync commit (a run that shows only these has found nothing new):

- Both shipped cfgs hold every rule.
- Known limit: a full run created between the contract-only run's last listing and its pass is not
  seen. `NoStaleCarryAtPass` (the promise with no exemption) breaks in `Yield.cfg` in 10 steps:
  1. `Start`: `run1` starts.
  2. `Mark`: mark-lanes records `ci-lanes` pending.
  3. `Aggregate`: `run1`'s CI Status records success.
  4. `StepEnds`: that step finishes.
  5. `CStart`: a label flip starts its CI Status.
  6. `CList`: it lists the runs and sees only `run1`, the writer.
  7. `Start`: `run2` starts on the same head (a reopen, a ready flip or a base change), with no
     marker yet.
  8. `CRead`: it reads `run1`'s success.
  9. `CVerify`: it verifies `run1` as the writer.
  10. `CDecide`: it passes while `run2` is queued.

  A run created before the listing is held for; one created after it is invisible to the code. The
  owner's decision on this window is recorded on issue 15773.
- The seeded break (`yield-to-full-run: 'false'`, `Yield = FALSE` in a copy of either cfg) breaks
  `NoStaleCarry` in 11 steps: `run1` records success and its step ends, `run2` starts, the
  label-flip run reads `run1`'s success, lists the runs (`run2` queued, no marker yet), reads the
  status again unchanged, verifies `run1` as the writer and passes. The single read checks only
  who wrote the success, not what is in flight.

## Updating

When a covered file in `sync.yaml` changes, read the change against the model: a moved marker, a
changed `needs`, a changed Aggregate lane results input, or a repin of the ci-workflows composite
means the model may change. Read the pinned `report-ci-status/action.yml`, `run.sh` and
`aggregate-results/action.yml` at the new commit
(`gh api -H 'Accept: application/vnd.github.raw' 'repos/melodic-software/ci-workflows/contents/.github/actions/pr-require-checks/aggregate-results/run.sh?ref=<sha>'`)
and re-cite the changed lines in the model's comments. The names the model reads, for a search of
new code that touches the same state: in `WF`, the `ci-lanes` context, the `mark-lanes` job, the
ci-status job's `needs` and `if:`, the contract-only predicate (`labeled`, `unlabeled`, `edited`),
the `concurrency` group, and the Aggregate lane results step's `report-ci-status` pin and its
`yield-wait-seconds`, `rerun-contract-only-siblings` and `step-name` inputs; in `REPORT`, the
`continue-on-error` contract and draft steps and the `yield-to-full-run`,
`carry-forward-wait-seconds` and `yield-wait-seconds` it passes to `aggregate-results`; in `RUN`,
`write_status`, `list_in_flight_full_runs`, `read_newest_entry`, `read_carried_state`, `verify_carried_writer`, `verify_writer_step`,
`gate_step_outcome`, `verify_no_newer_verdict`, `writer_attempt_wrote`, `carried_postdates`,
`held_success_carries`, `yield_hold` and `fail_superseded`. A promise changed on purpose means a
rule changes, and only with the owner's yes. Never weaken a rule to make it hold. Move `commit` forward
only after confirming the model describes the code at the new commit, which must be on the default
branch; rerun both cfgs, the seeded break and the run without `VIEW`, and update the known results
above. When a change edits the covered code itself, its stale-coverage warning is expected until
it lands; move the sync commit in a follow-up change after it lands.

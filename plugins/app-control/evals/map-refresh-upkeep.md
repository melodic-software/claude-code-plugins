# Map refresh upkeep eval

The four `map-refresh-*` cases below measure `/app-control:map refresh`'s upkeep steps, one case per
behavior. A two-version compare runs them against the skill text before and after a change to
those steps.

## Cases

| Case | Behavior |
|---|---|
| `map-refresh-unattended-stale-ready-reports-unwritten` | an unattended stale Ready is reported with its corrected text, unwritten |
| `map-refresh-unreached-feature-names-prerequisite-and-command` | a feature not reached names its prerequisite and command; a reason without one is doc drift |
| `map-refresh-shared-launch-groups-same-state` | features needing the same app state share one launch when the launch model allows it |
| `map-refresh-spot-check-and-unmapped-sweep` | a cited claim its line does not support is dropped; an unmapped surface is reported with its source path |

Every grader is deterministic. Each one's samples hold at least one answer it must pass and one it
must reject. `/evals:validate` checks those samples in node, and the CLI runs the patterns in
JavaScriptCore (Bun), so a pattern change is checked under `bun` as well.

`drives-nothing` does not count `/app-control:drive cleanup`. Cleanup stops only what the run
started and drives no feature (`skills/drive/SKILL.md`, the `cleanup` row of Actions), and the live
pass requires it after each launch (`skills/map/reference/refresh.md`, § 5 invariant 2).

## Registered rule

This rule was written and committed before the compare's first run. A later change to it is named
as a deviation in the record.

- **Versions.** BEFORE is the app-control plugin at the pull request's merge parent from main, with
  the four case folders copied in from the head. AFTER is the head's app-control plugin.
- **Runs.** On the `sonnet` alias, 6 runs per case per side; on the `opus` alias, 3. Each run uses
  `claude plugin eval <copy> --case 'map-refresh-[su]*' --runs <n> --ablation none --scaffold
  --allow-tools Write Edit --keep-temp --judge-model opus --threshold 0.8 --max-cost-usd 5
  --no-publish`. `TMPDIR` is a directory of the run's own, never a shared one. After a usage-limit
  error, no new batch starts.
- **Metric.** The per-case with-arm mean score, and the paired change over cases that
  `noise-report.py <after> --baseline <before> --margin 0.05` prints.
- **INVALID.** A result file whose `run-validity.py --runs <n> --scaffolded` verdict is not VALID is
  no result. Its side is rerun once with the same settings. A second INVALID file ends the compare
  as not met for that model.
- **Met.** On both models, every counted file is VALID, the noise report prints `compare verdict:
  non-inferior at margin 0.05`, and it prints no `case drop` line.
- **Not met.** Any other outcome, `n too small to call` included. Graders are not changed after a
  run's numbers have been seen.

## Amendment 1 (withdrawn)

Withdrawn before any result was read; its runs were stopped and discarded. It raised sonnet's run
count against the owner's eval gate (below), and it followed a grader change made after the first
compare's numbers.

A deviation from the rule above, written and committed before the rerun it governs.

- **Why.** The first compare (the rule above, with the filter deviation the Record names) was not
  met.
  - Opus read `non-inferior at margin 0.05` (paired change +0.24, interval +0.02 to +0.46).
  - Sonnet read `not shown non-inferior at margin 0.05` (paired change +0.21, interval -0.07 to
    +0.48, over 4 cases).
  - One sonnet miss was a grader false fail: `reports-blocked-with-fix` rejected the correct
    citation `src/server.ts:11-12`. That grader was fixed in its own commit before this amendment;
    a range that starts or ends at line 12 now passes.
- **Selection.** Each side's plugin copy keeps only these four `map-refresh-*` case folders (any
  other is removed from both copies the same way), and the run selects them with
  `--case 'map-refresh-*'`. The CLI's `--case` glob has no bracket class, so the rule's
  `'map-refresh-[su]*'` matched nothing.
- **Runs.** Sonnet runs 12 per case per side; opus keeps 3. The basis: noise-report pairs the change
  over cases with a normal interval, Z·sd/√cases
  (`plugins/evals/skills/plugin-eval/scripts/noise-report.py`, `normal_interval`), and gives no
  run-count guidance. More runs narrow that interval only by cutting the sampling noise in each
  case's mean change. Doubling sonnet's runs halves that variance. Opus already read non-inferior
  at 3 runs with the lower end above zero, so it keeps its count and is rerun fresh.
- **Ceiling.** The sonnet invocations pass `--max-cost-usd 10`. At the first compare's
  list-price cost of 0.13 USD a sonnet run, 48 runs is about 6.2 USD, and a ceiling of 5 would end
  the pass partway. Opus keeps 5.
- **No pooling.** Runs from the first compare are not reused or pooled.
- **Unchanged.** The four cases, the versions rule, the flags other than `--case`, `--runs` and the sonnet ceiling, the
  INVALID rule, margin 0.05 and the met rule.
- **Last rerun.** This is the last rerun. A result that again reads not shown non-inferior is recorded
  as not met, and the hold stays until the skill text changes. The eval does not change to reach
  a verdict.

## Record

The first four-case compare. It used the rule registered above (b9ad83fa8a) with one deviation: its
case filter. It ran before at main `35c687f674` and after at `a70e47f513`, with sonnet at 6 runs a
side and opus at 3. All four result files read `verdict: VALID`.

- **Filter, a deviation from the registered rule.** The rule's `--case 'map-refresh-[su]*'` matched
  no case, because the CLI's glob has no bracket class; that attempt ran no model. The scored runs
  used `--case 'map-refresh-*'` on all four invocations (sonnet and opus, before and after). Each
  result file records it as `suite.caseFilter: map-refresh-*`.
- **Selection.** In the plugin copy of each side, the same way on both, the fifth `map-refresh-*`
  case folder, `map-refresh-ticket-branch-commits-there`, was removed. Each result file lists the
  same four scored cases: `map-refresh-shared-launch-groups-same-state`,
  `map-refresh-spot-check-and-unmapped-sweep`,
  `map-refresh-unattended-stale-ready-reports-unwritten` and
  `map-refresh-unreached-feature-names-prerequisite-and-command`.

| Case | Sonnet before → after | Opus before → after |
|---|---|---|
| stale Ready | 1.000 → 0.933 | 1.000 → 1.000 |
| unreached | 0.611 → 1.000 | 0.667 → 1.000 |
| shared launch | 1.000 → 1.000 | 0.889 → 1.000 |
| spot-check and sweep | 0.500 → 1.000 | 0.500 → 1.000 |

- **The rule's interval clause.** Sonnet read `not shown non-inferior at margin 0.05` (change +0.21,
  interval -0.07 to +0.48). Opus read `non-inferior at margin 0.05` (+0.24, +0.02 to +0.46).
- **The reading applied.** The owner's eval gate, decided after this rule was registered, applies the
  interval test only at about 20 cases or more. Under it, a loss reading starts a trace read of each
  dropped case and an Opus confirm, and only a loss traced to the changed text counts
  ([claude-code-plugins#16672](https://github.com/melodic-software/claude-code-plugins/issues/16672#issuecomment-6935228111)).
  With 4 cases, the interval test does not apply.
- **Case drops.** Neither noise report prints a `case drop` line, and no case fell by a third.
- **The one dip.** Sonnet stale Ready fell to 0.933: `reports-blocked-with-fix` missed runs 2 and 3,
  each "pattern not found". The trace of run 2 shows a correct reply that the grader failed. The reply
  reads "`src/server.ts:11-12` reads `// The shop moved off 3000 so it can sit beside the admin
  console.` followed by `app.listen(4100, "127.0.0.1");`", and gives the corrected Ready, unwritten.
  Sonnet run 3's failing trace was not read: its kept sandbox was removed first, so its miss is not
  traced.
- **Opus confirm.** Non-inferior, every case at 1.000 after.
- **Result under the gate: met.** No case dropped, the one miss read (run 2) traces to the grader and
  not to the changed text, and Opus confirms.

The grader fix that accepts such a range (b25f07b3e0) came after these numbers. It is a disclosed
follow-up fix and was not a scoring input.

## Registration: Reset that restarts the app on a reused instance

This registration covers the drive change that re-records the launch after a `## Reset` that restarts
the app. It was written and committed before its run, under the owner's eval gate.

- **Case.** `drive-reused-launch-reset-restart-rerecords`. It passed a 2-run sonnet smoke (VALID,
  1.00 both runs) before this registration; the smoke is not a scoring input.
- **Sides.**
  - BEFORE is the app-control plugin at `b30564372304`, with this case's folder copied in.
  - AFTER is the plugin at `4919ea4d2c`, which is `e0f2cc64b0` plus a shellcheck-only scaffold
    change whose output is byte-identical. Only `drive/SKILL.md` and `drive/reference/evidence.md`
    differ from BEFORE.
- **Runs.**
  - Sonnet, 3 runs a side.
  - The command: `claude plugin eval <copy> --case 'drive-reused-launch-reset-restart-rerecords'
    --model sonnet --runs 3 --ablation none --scaffold --trust-plugin --keep-temp --judge-model opus
    --threshold 0.8 --max-cost-usd 5 --no-publish`.
  - `TMPDIR` is a directory of the run's own.
- **INVALID.** A file whose `run-validity.py --runs 3 --scaffolded` verdict is not VALID is no result.
  Its side is rerun once with the same settings.
- **Loss.** The AFTER case mean is below the BEFORE case mean. A loss starts two checks:
  - a trace read of each AFTER run that a grader failed;
  - an opus run of both sides at 3 runs a side.
  Only a loss traced to the changed drive text counts.
- **Met.** Both files are VALID and there is no counted loss.

**Result.**

- Both files read `verdict: VALID`. Both ran the registered filter with no deviation: each records
  `suite.caseFilter: drive-reused-launch-reset-restart-rerecords` and scores that one case.
- BEFORE scored 1.00, 1.00, 1.00, and AFTER scored 1.00, 1.00, 1.00. The noise report prints
  `compare verdict: n too small to call (cases scored in both results: 1; 3 or more are needed)`.
- No loss, so no opus confirm ran. The result is met.
- The case does not separate the two texts: BEFORE run 1 also stops pid 7311, relaunches and replaces
  the launch entry. The rule is now written in drive's text, but on sonnet the case measured no
  difference.

## Registration: smoke of the attended stale Ready and drive blocked-entry cases

This registration covers two new cases, each closing a review finding that a done-when half had no
case. It was written and committed before their smoke, under the owner's eval gate, where a new case
gets a 1 to 3 run smoke.

- **Cases.**
  - `map-refresh-attended-stale-ready-retries-once`: the attended half of the stale-Ready rule.
  - `drive-blocked-entry-names-prerequisite-and-command`: drive's half of the blocked-entry rule.
- **Side.** The head's app-control plugin, the commit that adds this registration. A smoke is not a
  before-and-after compare.
- **Runs.** Sonnet, 3 runs per case. The command: `claude plugin eval <copy> --case '<case name>'
  --model sonnet --runs 3 --ablation none --scaffold --trust-plugin --keep-temp --judge-model opus
  --threshold 0.8 --max-cost-usd 5 --no-publish`, once per case. `TMPDIR` is a directory of the
  run's own.
- **INVALID.** A file whose `run-validity.py --runs 3 --scaffolded` verdict is not VALID is no
  result. It is rerun once with the same settings.
- **A fail.** A run scoring below 1.00. Its trace is read:
  - When the reply is correct and a grader missed it, that is a grader defect.
  - When the reply follows the skill text and is still wrong, that is a defect in the skill text. It
    is reported, and no grader is loosened to pass it.

**Result.** Both smokes ran on the plugin at `73f59cccc4`. That is the registering commit
`218c860e55` plus a regex respelling, `restore[sd]?|restoring`, which gives every sample the same
verdict under node and bun. Each smoke used its case name as `--case`. Both files read
`verdict: VALID`.

- `map-refresh-attended-stale-ready-retries-once`: 1.00, 1.00, 1.00. Run 1 runs no further Ready,
  reports blocked and puts `curl -fsS http://127.0.0.1:3000/healthz` back into `## Ready`, citing
  refresh.md § 5.
- `drive-blocked-entry-names-prerequisite-and-command`: 1.00, 1.00, 1.00. Run 1's `blocked` entry
  carries `prerequisite` (the write grant) and `attempted` (`cli/shop export --env staging`).
- No run failed, and neither case found a defect in the skill text.

## Registration: smoke of the data-source and lesson cases

This registration covers three new cases, one per new rule. It was written and committed before
their smoke, under the owner's eval gate, where a new case gets a 1 to 3 run smoke.

- **Cases.**
  - `drive-ready-lists-missing-sources`: ready reports each environment's data sources and the
    kinds it is missing, and reads none.
  - `drive-report-lists-lessons`: a drive report lists its lessons as refresh lines and drive
    writes no Gotchas.
  - `map-refresh-places-handed-in-lessons`: refresh places a lesson handed in from a
    `/debugging:debug` report.
- **Side, runs, INVALID and a fail.** As the smoke above: the head's app-control plugin, sonnet, 3
  runs per case, the same command once per case.

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

## Amendment 1

A deviation from the rule above, written and committed before the rerun it governs.

- **Why.** The first compare under the rule was not met.
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

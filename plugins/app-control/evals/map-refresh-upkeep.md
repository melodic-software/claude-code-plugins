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

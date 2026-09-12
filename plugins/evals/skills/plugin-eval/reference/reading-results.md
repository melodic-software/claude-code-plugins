# Reading `aggregate-result.json`

Read when a run has written its JSON, or when a wrapper needs to consume one. The document is the
statement of record: with `--json <file>` the terminal summary table is suppressed entirely.

## Contents

- [Read order](#read-order)
- [Document fields](#document-fields)
- [Per-case fields](#per-case-fields)
- [Per-run fields](#per-run-fields)
- [Per-grader fields](#per-grader-fields)
- [What a delta does and does not say](#what-a-delta-does-and-does-not-say)

## Read order

1. `partial`. When `true`, `partialReason` is `cost_ceiling`, `interrupted`, or `auth_failed`. The
   suite did not finish; report that and keep the document out of any trend. The check is done when
   the field has been read, not inferred from the exit code.
2. Every run in both arms: `skippedPaidGraders` and `error`. Either one makes its case not
   comparable. Say "not comparable" and name which run; do not report the case's number.
3. `cases[].aggregates.delta`. It is **omitted** when the arms are not comparable, and so is
   `scoreWithout`. An omitted field is never zero.
4. Only then, the delta itself.

## Document fields

| Field | Meaning |
|---|---|
| `schemaVersion` | Document version. The schema is additive, so ignore fields you do not recognize rather than failing on them |
| `claudeVersion` | The binary that ran the suite. Read it into any trend store; it is what makes an old result interpretable after an upgrade |
| `startedAt`, `durationSeconds` | Start timestamp and wall-clock |
| `costUsd` | List-price estimate for the whole suite, judge calls included |
| `partial`, `partialReason` | The gate. `cost_ceiling`, `interrupted`, or `auth_failed` |
| `suite` | The run's own configuration: `root`, `ablation`, `threshold`, `concurrency`, `plugins`, and `caseFilter` when `--case` was passed. Compare it before comparing two documents |
| `aggregates` | `casesTotal`, `casesPassed`, `overallScore`, `overallPassRate`, `meanDelta` |
| `cases` | One entry per case, in the order they ran |

## Per-case fields

`name`, `dir`, `source`, `promptMarkdown`, `runsPerCase`, `timeoutSeconds`, `maxTurns`, `graders`,
`arms`, and `aggregates`. `arms` holds `with` and `without`, each a list of runs; under
`--ablation none` only `with` is present, and `suite.ablation` records which mode ran.

`cases[].aggregates` carries `score` and `passRate` for the with-arm, plus `scoreWithout`,
`passRateWithout`, and `delta` when the arms are comparable. Observed on a suite where one
without-run lost its judge to the ceiling: `scoreWithout` and `delta` were both absent while
`passRateWithout` was still present. Read `delta` alone, and treat its absence as a stop.

## Per-run fields

`costUsd`, `durationSeconds`, `error`, `graders`, `judgeCostUsd`, `passed`, `score`,
`skippedPaidGraders`, `startedAt`, `tracePath`, `turns`.

- `error` is `null` or the reason the run ended abnormally, such as a timeout. A non-null `error`
  does **not** imply score 0; the run is still graded on what it produced, which is why a rate limit
  mid-suite reads as a regression rather than as an outage.
- `aborted` appears when a mock's `expect:` or `abort_when` stopped the run, carrying `server`,
  `tool`, and `reason`. It scores 0 while `error` stays `null`.
- `skippedPaidGraders: true` means the cost ceiling skipped this run's judge calls. The skipped
  graders are still scored, as failures, so the arm is depressed rather than obviously broken.
- `tracePath` points at a per-run temp directory the runner deletes unless the run passed
  `--keep-temp`. Decide on that flag before the run.
- **No field records the model that ran the case.** Pin `--model` and `--judge-model` and record the
  invocation yourself if a trend needs to know.

## Per-grader fields

`name`, `passed`, `weight`, `explanation`, `withOnly`, `scored`. An `llm` grader adds `judgeVotes`
(one boolean per vote) and `evidence` (the excerpt the judge read).

- `scored: false` with `withOnly: true` is the plugin-fired indicator. Measured on a `tool_used`
  grader on `tool: Skill` that carried no `arm:` key at all: the with-arm run reported it
  `withOnly: true, scored: false`, and the without-arm run's grader list **omitted it entirely**.
  A `passed: false` grader inside a 1.00 run is that exclusion, by design.
- The same grader under `--ablation none` reported `withOnly: false, scored: true`: nothing is
  excluded in that mode, and `arms` carries only `with`.
- When every grader in a case is such a grader, the fallback scores them normally.
- `explanation` carries the reason, and it is where a ceiling skip is visible:
  `"skipped: cost ceiling"` on a grader with `scored: true` and `passed: false`.

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| The field names and shapes above, including the omission of `delta` and `scoreWithout` on incomparable arms and the `"skipped: cost ceiling"` explanation string | <https://code.claude.com/docs/en/plugin-evals> plus four `aggregate-result.json` documents measured from this plugin's own suite, verified 2026-09-12 | Recheck trigger: `schemaVersion` increments, or a documented field is renamed. Then re-read the page, re-derive the tables against a freshly written document, and refresh this record with the outcome. The schema is additive, so an unknown field is not a firing |

## What a delta does and does not say

- The delta is the with-arm case score minus the without-arm case score. A run score is the weighted
  fraction of graders passed; a case score is the mean over runs; a case passes at or above
  `--threshold`.
- 1.00 in both arms proves the plugin contributed nothing to that case.
- Absolute scores are not comparable across ablation modes: under `--ablation none` no grader is
  excluded, so the same suite scores differently. Hold the mode fixed or the trend line is fiction.
- A single run is a smoke test. The defaults exist because a non-deterministic agent tells you
  little in one sample, and pinning both models buys comparability, not determinism.

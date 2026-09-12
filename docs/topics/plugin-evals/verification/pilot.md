# Pilot: the `evals` plugin suite and its measured Δ

Evidence for acceptance criterion 3 (the pilot suite runs locally under the ceiling, writes
`aggregate-result.json` with a delta per case, and at least one case shows a positive delta).
Values are distilled from each pass's JSON; the JSON files and `results/` directories stay
untracked.

## Setup

- Target: `plugins/evals` (path target, so results land under `plugins/evals/evals/results/`).
- Cases: `grading-method-choice`, `measurable-criterion`, `control-no-trigger`; each
  `allowed_tools: [Read, Glob, Grep, Skill]`, `max_turns: 10`, `runs: 3`.
- Command shape: `claude plugin eval plugins/evals --trust-plugin --json <file> --max-cost-usd 2
  --threshold 0.8 --no-publish`, run from the PowerShell tool.
- Claude Code 2.1.269 (`claudeVersion` in every JSON). Ablation `with-without`, concurrency 1,
  judge model the default (`haiku`).
- Child-session model: the JSON records no model; the probe runs below, launched with the same
  defaults, resolved to `claude-opus-5`. Judge calls cost about 0.002 USD per run.

## Term-uniqueness probe (before any pass)

The case-1 prompt was sent to `claude -p` from an empty directory with `--setting-sources
project,local` and `--tools "Read,Glob,Grep,Skill"`, three times without the plugin and twice with
`--plugin-dir` pointing at the worktree copy. Both with-runs invoked `evals:methodology`, so
`--plugin-dir` resolved the worktree copy, not the installed one (both installed copies were
disabled). A term qualified only if absent from every without-run and present in every with-run.

| Candidate | Without (3) | With (2) | Verdict |
|---|---|---|---|
| `showpiece` | 0 | 2 | kept |
| `fastest, most reliable, most scalable` | 0 | 2 | kept |
| `headline metric` / `headline number` | 0 | 2 | kept |
| `read a sample` / `read samples` | 0 | 2 | kept |
| `ladder` | 0 | 0 | rejected (the with-arm paraphrases the heading) |
| `different model` | 3 | 2 | rejected (base knowledge) |

The outcome grader for case 1 is the alternation of the four kept terms, `flags: i`, `arm: both`.
The control prompt (pytest fixture sharing) invoked no skill on either side and named
`conftest.py` on both. Probe spend: about 0.6 USD across the seven runs, outside the pass tally.

## Pass 1 (full suite)

| Case | WITH | W/OUT | Δ | Notes |
|---|---|---|---|---|
| grading-method-choice | 1.00 | 0.00 | +1.00 | `skill-fired` indicator passed in all three with-runs |
| measurable-criterion | 1.00 | (omitted) | (omitted) | third without-run skipped its judge at the ceiling (`skippedPaidGraders: true`), so the arms were not comparable; the two graded without-runs passed |
| control-no-trigger | 1.00 | 1.00 | 0.00 | no Skill call in any of the six runs |

`partial: false`, exit 0, `costUsd` 2.06, 287 s, `meanDelta` 0.50 over the two comparable cases.

One without-arm run of `grading-method-choice` took 7 turns and cost 0.82 USD; the other eight
without-runs cost 0.04 to 0.08. The ceiling is checked before each run launches, so every run
still ran, but the last judge call was skipped once the tally crossed 2 USD. The runner's summary
line reads "cost ceiling $2 exceeded: $2.06 spent by runs already in flight when it was crossed;
nothing was skipped", which describes runs, not judge calls.

## Pass 2 (full suite, unchanged)

| Case | WITH | W/OUT | Δ | Notes |
|---|---|---|---|---|
| grading-method-choice | 1.00 | 0.00 | +1.00 | indicator passed in all three with-runs; every without-run failed the regex |
| measurable-criterion | (not run) | (not run) | (not run) | skipped whole at the ceiling |
| control-no-trigger | 1.00 | 1.00 | 0.00 | as pass 1 |

`partial: true`, `partialReason: cost_ceiling`, exit 2, `costUsd` 2.71, 214 s.

All three without-arm runs of `grading-method-choice` took 6 to 9 turns and cost 0.70 to 0.75 USD
each, against 4 turns and about 0.10 USD for every with-arm run. Pass 1's 0.82 USD run was not an
outlier: without the plugin the model spends turns on that prompt, and the cost of a full pass is
about 2.7 USD at this model. Nothing in the suite changed between the passes. The per-run traces
live in temp directories the runner deletes, so what those turns did is unrecorded; `--keep-temp`
preserves them and is the flag for the Phase 6 confirming pass.

## Pass 3 (`--case measurable-criterion`, ceiling 1.2)

| Case | WITH | W/OUT | Δ | Notes |
|---|---|---|---|---|
| measurable-criterion | 1.00 | 1.00 | 0.00 | judge voted PASS 3 of 3 on all six runs; indicator passed in all three with-runs |

`partial: false`, exit 0, `costUsd` 0.48, 101 s. The base model already rewrites the criterion to
the four properties, so this case measures nothing the plugin adds; it stays as a regression guard
on the `llm` grader path and the indicator.

## Tally

| Pass | Scope | `costUsd` | Cumulative |
|---|---|---|---|
| 1 | full | 2.06 | 2.06 |
| 2 | full | 2.71 | 4.77 |
| 3 | one case | 0.48 | 5.25 |
| trust probe | one case, one arm, one run | 0.11 | 5.36 |

Phase 2 ceiling: three passes, 6 USD. Whole pilot including the Phase 6 confirming pass: 8 USD.
With the 0.61 USD term-uniqueness probe, the session's total spend is 5.97 USD of the 8 approved.

## Verdict against the phase's sanity check

- Every case has a `delta` from a pass whose runs all finished (`error` and `aborted` null, no
  `skippedPaidGraders`): cases 1 and 3 from pass 1 and pass 2, case 2 from pass 3. One delta is
  positive (+1.00, reproduced in two passes at 6 of 6 with-runs passing and 6 of 6 without-runs
  failing).
- Not met literally: no single JSON holds all three cases with all three deltas under a 2 USD
  ceiling, because a full pass costs about 2.7 USD at the default model. The ceiling is the
  approved number, so the decision is the user's: raise `--max-cost-usd` to 3 for the Phase 6
  confirming pass, pin a cheaper `--model` for the child sessions, or accept split-invocation
  evidence.

## Observations for the runner skill

- A pass that crosses the ceiling can end with `partial: false`, exit 0, and a case with no
  `delta`: the ceiling skips judge calls, not runs, and only the JSON shows it (`skippedPaidGraders`
  on the run, `explanation: "skipped: cost ceiling"` on the grader). A pass that crosses it
  earlier skips whole cases and reports `partial: true` with exit 2.
- Without-arm cost is not the with-arm cost minus the plugin: here it was seven times higher on
  the knowledge case. Estimate from a probe of both arms, with headroom, not from the mean.
- `--trust-plugin` persists: after the first pass, a rerun without the flag under `--json` (no TTY)
  launched instead of refusing, so the trust decision covered the repository for later runs.
- `--json <file>` suppresses the terminal summary table; the JSON is the only record.
- Read of the plugin's own reference files from inside the with-arm was not observed in the JSON
  (no per-run tool list); the with-arm answered from the skill hub in the probe when a Read outside
  the workspace was denied, and the hub alone carried every kept term.

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
- Claude Code 2.1.269 for passes 1 to 3 and 2.1.270 for passes 4 and 5 (`claudeVersion` in each
  JSON). Ablation `with-without`, concurrency 1, judge model the default (`haiku`).
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

## Pass 4 (Phase 6 confirming pass, full suite, no ceiling, `--keep-temp`)

Run 2026-09-13 against the merged branch (the two new skills and the rewritten descriptions in
place), at Claude Code 2.1.270, with `--max-cost-usd` omitted on the user's instruction that spend
is unrestricted, and `--keep-temp` so the per-run traces survived. Nothing in the three case files
changed since pass 1.

| Case | WITH | W/OUT | Δ | Notes |
|---|---|---|---|---|
| grading-method-choice | 1.00 | 0.00 | +1.00 | indicator passed in all three with-runs; every without-run failed the regex (0 of 6 terms in each) |
| measurable-criterion | 1.00 | 1.00 | 0.00 | judge voted PASS 3 of 3 on all six runs; indicator passed in all three with-runs |
| control-no-trigger | 1.00 | 1.00 | 0.00 | no tool call of any kind in any of the six runs |

`partial: false`, exit 0, `costUsd` 3.07, 330 s, `meanDelta` 0.33 over three comparable cases,
`casesPassed` 3 of 3. No run carried `skippedPaidGraders` or a non-null `error`. This is the
single-JSON form the Phase 2 sanity check could not fund: three cases, three deltas, one positive.

Per-run turns and cost: the knowledge case's without-runs took 6 turns each at 0.55 to 0.73 USD;
its with-runs 4 turns at 0.11 to 0.12; `measurable-criterion` with-runs 4 turns at about 0.12,
without-runs 1 turn at 0.05 to 0.06; `control-no-trigger` 1 turn at 0.04 to 0.07 in both arms.

## What the kept traces show

Each run's `tracePath` is a single-session JSONL (`system/init`, `assistant`, tool-result `user`
lines, one `result`). The child session ran as `claude-opus-5` (`claude-opus-5[1m]` in the init
line), `permissionMode: dontAsk`, in a throwaway working directory.

- **The without-arm's turns on the knowledge case go to the bundled `claude-api` skill.** All three
  without-runs invoked it (two after the provider-grep skip check that skill prescribes), then
  grepped and read its `build-eval.md` reference from the bundled-skills directory. The injected
  skill body is about 88,500 characters against about 6,400 for this plugin's methodology hub,
  which accounts for the cost gap. No without-run read anything under the working directory and
  none searched the web. Each answer was a sound grading recommendation in that skill's own
  vocabulary and contained none of the four probed terms, so the regex separated the arms on
  wording, as designed.
- **The with-arm never reads a `reference/` spoke.** All six with-runs of the two knowledge cases
  called `Skill` with `evals:methodology` and then attempted a `Read` of `reference/grading.md` or
  `reference/success-criteria.md`; every attempt was refused with `File is in a directory that is
  denied by your permission settings` and appears in the result's `permission_denials`. The
  injected skill body names the plugin's real on-disk directory, which sits outside the sandbox's
  permitted roots. The with-arm's answers said so and answered from the hub, and the hub alone
  carried the probed terms (3 or 4 of the 6 term forms per run). The measured lift on this suite
  is therefore the hub `SKILL.md`, not the spokes.
- **`measurable-criterion` is base knowledge.** The without-arm answered in one turn with zero
  tool calls and passed the judge every time, which settles the Phase 2 question of whether to
  tighten its rubric: no rubric separates arms that produce the same correct answer, so the case
  stays as a regression guard on the `llm` grader path and the indicator.

## Pass 5 (through the skill's `run` action, unlimited, no `--keep-temp`)

Run 2026-09-13 by `claude -p "/evals:plugin-eval run plugins/evals …"` with the unlimited option
supplied through `--settings`, to exercise acceptance criterion 5's "the run proceeds without a
prompt" (transcript in `preflight.md`). The skill invoked the CLI with no `--max-cost-usd`.

| Case | WITH | W/OUT | Δ | Notes |
|---|---|---|---|---|
| grading-method-choice | 1.00 | 0.00 | +1.00 | indicator passed in all three with-runs; every without-run failed the regex |
| measurable-criterion | 1.00 | 1.00 | 0.00 | judge PASS on all six runs; without-runs 1 turn each |
| control-no-trigger | 1.00 | 1.00 | 0.00 | as every pass |

`partial: false`, exit 0, `costUsd` 3.20, 381 s, `meanDelta` 0.33. The knowledge case's
without-runs took 8 to 9 turns at 0.60 to 0.71 USD; one with-run took 6 turns at 0.15. The
positive delta is now reproduced in four passes.

## Tally

| Pass | Scope | `costUsd` | Cumulative |
|---|---|---|---|
| 1 | full | 2.06 | 2.06 |
| 2 | full | 2.71 | 4.77 |
| 3 | one case | 0.48 | 5.25 |
| trust probe | one case, one arm, one run | 0.11 | 5.36 |
| 4 | full, no ceiling | 3.07 | 8.43 |
| 5 | full, no ceiling, via the skill | 3.20 | 11.63 |

Phase 2 ceiling: three passes, 6 USD. The plan approved 8 USD for the whole pilot; on 2026-09-13
the user lifted the ceiling for Phase 6. With the 0.61 USD term-uniqueness probe, the pilot's
total list-price spend is 12.24 USD. A killed first attempt at pass 5 (the session backgrounded
the CLI and exited) started one run and recorded no cost.

## Verdict against the phase's sanity check

- Every case has a `delta` from a pass whose runs all finished (`error` and `aborted` null, no
  `skippedPaidGraders`): cases 1 and 3 from pass 1 and pass 2, case 2 from pass 3. One delta is
  positive (+1.00, reproduced in two passes at 6 of 6 with-runs passing and 6 of 6 without-runs
  failing).
- Phase 2 did not meet the single-JSON form under a 2 USD ceiling, because a full pass costs about
  2.7 USD at the default model. Pass 4 met it in Phase 6 with the ceiling lifted: one JSON,
  `partial: false`, three deltas, +1.00 reproduced a third time.

## Observations for the runner skill

- A pass that crosses the ceiling can end with `partial: false`, exit 0, and a case with no
  `delta`: the ceiling skips judge calls, not runs, and only the JSON shows it (`skippedPaidGraders`
  on the run, `explanation: "skipped: cost ceiling"` on the grader). A pass that crosses it
  earlier skips whole cases and reports `partial: true` with exit 2.
- Without-arm cost is not the with-arm cost minus the plugin: here it was four to seven times higher on
  the knowledge case. Estimate from a probe of both arms, with headroom, not from the mean.
- `--trust-plugin` persists: after the first pass, a rerun without the flag under `--json` (no TTY)
  launched instead of refusing, so the trust decision covered the repository for later runs.
- `--json <file>` suppresses the terminal summary table; the JSON is the only record.
- The JSON carries no per-run tool list, so whether the with-arm reads the plugin's reference files
  is visible only in a kept trace; pass 4's traces settled it (denied, every time), and the hub
  alone carried every kept term.

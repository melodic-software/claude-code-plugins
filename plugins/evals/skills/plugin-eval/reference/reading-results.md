# Reading `aggregate-result.json`

Read when a run has written its JSON, or when a wrapper needs to consume one. The document is the
statement of record: with `--json <file>` the terminal summary table is suppressed entirely.

## Contents

- [Read order](#read-order)
- [Denials](#denials)
- [Document fields](#document-fields)
- [Per-case fields](#per-case-fields)
- [Per-run fields](#per-run-fields)
- [Per-grader fields](#per-grader-fields)
- [What a delta does and does not say](#what-a-delta-does-and-does-not-say)
- [Noise report](#noise-report)

## Read order

1. `scripts/run-validity.py <json> --runs <n>`. Only `verdict: VALID` lets a number be reported;
   on `verdict: INVALID`, report INVALID and its reasons. The command and its exits are in
   [SKILL.md, Reading the delta](../SKILL.md#reading-the-delta). Add `--scaffolded` only when the
   eval ran with `--scaffold`. Without the flag, the `scaffold` check fails each case whose
   `case.yaml` sets `context.scaffold_script`; a `case.yaml` it cannot locate or read leaves that
   check unchecked. When the comparison measures whether a skill fires, as on the base side of a
   change that makes it fire, name each such case with `--measured-fire <case>`: its misses are
   reported as a measured rate, not a failure, and every other check still applies.

   - **Pointer**: [Add setup or history with case.yaml](https://code.claude.com/docs/en/plugin-evals#add-setup-or-history-with-case-yaml);
     the `--scaffold` row of [Command options](https://code.claude.com/docs/en/plugin-evals#command-options);
     [JSON result](https://code.claude.com/docs/en/plugin-evals#json-result)
   - **As of**: 2026-10-27
   - **Recheck trigger**: that first section changes when a `scaffold_script` runs, the JSON result
     gains a field recording `--scaffold`, or a release note touches `--scaffold`
2. `partial`. When `true`, `partialReason` is `cost_ceiling`, `interrupted`, or `auth_failed`. The
   suite did not finish; report that and keep the document out of any trend. The check is done when
   the field has been read, not inferred from the exit code.
3. Every run in both arms: `skippedPaidGraders` and `error`. Either one makes its case not
   comparable. Say "not comparable" and name which run; do not report the case's number.
4. `cases[].aggregates.delta`. It is **omitted** when the arms are not comparable, and so is
   `scoreWithout`. An omitted field is never zero.
5. Only then, the delta itself.
6. Run the [noise report](#noise-report) over the same file and read its lines before calling any
   delta a gain.

## Denials

How the validity gate classifies a denied tool call, after the FAIL rule in
[SKILL.md, Reading the delta](../SKILL.md#reading-the-delta) (a with-arm denial aimed at, under or
above the plugin's directory, or with no absolute path or no known plugin directory).

- A Bash denial's paths are its command's absolute arguments, plus no path when it has an
  expansion or a relative word other than a flag, or does not parse.
- Two kinds of denial are set aside before any other rule judges the run, each a warning that never
  counts toward a FAIL: a named call other than Skill aimed only under the run's own plugin-data
  directory (`<sandbox>/config/plugins/data`), and a `Read`, `Grep` or `Glob` aimed only under the
  session's own `<sandbox>/config/projects/*/*/tool-results/`, where it reads back output it already
  received. A Bash pipeline of `cat`, `head`, `wc`, `grep` and `sed -n` that reads only there is set
  aside the same way. Compare such a run's score only with runs denied the same way. Any other Bash call (a
  redirect, another command or operator, an unquoted glob, brace or `$`, or a path outside that
  directory), a write, or any other
  path in the config directory (`settings.json` included) keeps the rules below.
- One exception overrides that FAIL: a denial of the same named call other than Skill (tool and
  target) in every run of its case, in both arms, is a warning, with or without an absolute path,
  unless an absolute path it names is at, under or above the plugin's directory. The environment
  denied it with or without the plugin, such as a user-scope read of `~/.claude/standards`. In an
  A/B pass, gate each version's result file.
- Any other denial, in either arm, is a warning only when its case has denial-free runs in that arm
  and its run scored the same as each; otherwise it is a FAIL.
- A run at 0 turns whose trace holds assistant messages ran a slash-invoked `context: fork` skill
  in a forked session, and the gate lists it under `session started` without failing it.
- An invocation probe's denial of a named call other than Skill is a warning when it follows the
  graded Skill call, or the run held a should-not-fire case whose denial-free runs all held; the
  gate prints each probe case's fire counts with and without denials.
- An invocation probe is a case whose `prompt.md` tags include `invocation-probe`, as
  `/skill-quality:check measure-invocation` emits it. Its should-fire misses are the trigger rate
  it measures: `skill fired` reports them as a warning with per-case counts, never a FAIL. Run
  errors and denials keep their full force, apart from the two probe exceptions above and a
  max-turns error after the graded Skill call. `probe tools` warns when a probe run could call
  Read, Glob, Grep or Agent, the tools the emitted README's run line removes, or its trace has no
  init tools list; when no probe run's list can be read, the check is UNCHECKED.

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

Count each arm's rows for the run count, never `runsPerCase`: under `--runs 2` at Claude Code
2.1.287 every case reported `runsPerCase: 3` while each arm held 2 rows.

- **Basis**: an `aggregate-result.json` from this plugin's own suite under `--runs 2`, Claude Code
  2.1.287; no docs page defines `runsPerCase`
  (<https://code.claude.com/docs/en/plugin-evals#json-result>).
- **As of**: 2026-10-01
- **Recheck trigger**: the plugin-evals page documents `runsPerCase`, or a run's `runsPerCase`
  matches its row count under `--runs`. Then update this paragraph.

A case whose case.yaml sets `context.history_file` runs with-arm only from a path target even
under `suite.ablation: with-without`: its `arms` holds no `without` key at all, and it has no
delta. `run-validity.py` accepts that shape as single-arm by design and warns; an empty or short
`without` list still fails the row count.

- **Basis**: two `aggregate-result.json` files from path-target runs at Claude Code 2.1.316, with
  `suite.ablation: with-without`, where every `history_file` case held 3 with-arm rows and no
  `without` key; no docs page states the single-arm rule
  (<https://code.claude.com/docs/en/plugin-evals#json-result>).
- **As of**: 2026-11-01
- **Recheck trigger**: the plugin-evals page documents how `history_file` interacts with
  `--ablation`, or a path-target run records a `without` arm for a `history_file` case.

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

The field names above are this file's reading index; the omission of `delta` and `scoreWithout`
on incomparable arms and the `"skipped: cost ceiling"` explanation string are measured from six
`aggregate-result.json` documents from this plugin's own suite (the last two at 2.1.270 with every
case complete), read 2026-09-13.

- **Pointer**: when a field's meaning matters to a gate, fetch
  [JSON result](https://code.claude.com/docs/en/plugin-evals#json-result) live.
- **As of**: 2026-10-11
- **Recheck trigger**: `schemaVersion` increments, or that section renames or drops a field. Then
  re-derive the tables against a freshly written document. The schema is additive, so an unknown
  field is not a firing.

## What a delta does and does not say

- The delta is the with-arm case score minus the without-arm case score. A run score is the weighted
  fraction of graders passed; a case score is the mean over runs; a case passes at or above
  `--threshold`.
- 1.00 in both arms proves the plugin contributed nothing to that case.
- Absolute scores are not comparable across ablation modes: under `--ablation none` no grader is
  excluded, so the same suite scores differently. Hold the mode fixed or the trend line is fiction.
- A single run is a smoke test. The defaults exist because a non-deterministic agent tells you
  little in one sample, and pinning both models buys comparability, not determinism.
- A grader that cannot pass without the plugin (every `tool_used` on `tool: Skill`, plus anything
  `arm: with-only`) is excluded from scoring in both arms ([Per-grader fields](#per-grader-fields)).
  `arm: both` forces scoring in both arms, which is what a must-not-invoke check (`min: 0` **and**
  `max: 0`) needs.
- Copy a plugin whose directory is named `evals` under another name before a run. Pointer: the
  probe pair in [records.md](records.md#spoke-reach), as of 2026-10-31; recheck on a Claude Code
  release by re-running one case with `--keep-temp`. Check the trace for a denied `Read` before
  crediting a spoke.

## Noise report

`scripts/noise-report.py` reads one `aggregate-result.json` and prints noise lines beside its
scores. It makes no model call and spends nothing. SKILL.md carries the full command; relative to
this skill's directory it is:

```bash
python3 scripts/noise-report.py results.json --threshold <the run's --threshold> --interval-method <normal|wilson|jeffreys> --grader-agreement
```

Pass the `--threshold` the run used, the `interval_method` setting as `--interval-method`, and
`--grader-agreement` when the `grader_run_twice` setting is on. A partial result prints one line
and nothing else. An interval method other than `normal`, `wilson` or `jeffreys` falls back to
`normal` with one line saying so. Exit 0 means the report printed; exit 2 means the file could not
be read or an argument was malformed.

| Line | What to do with it |
|---|---|
| `not comparable: case <name> (<reason>)` | Name the case and leave it out of any claim. The report has already left it out of every number |
| `score check: ...` | The run's reported score and its graders disagree. Read that run's graders before using its number |
| `<arm>-arm mean: ...` | Report each mean with its interval, never the mean alone |
| `cost: ...` | Report it beside the scores, in the same answer as the delta |
| `near ceiling: ...` | The baseline leaves no headroom, so the suite has almost no room to show a gain. Add a case the model fails without the plugin |
| `delta ...` and `verdict: within noise` or `verdict: n too small to call` | The gain is not established, whatever the delta's sign or size |
| `delta ...` and `verdict: the interval excludes 0` | Report the delta with its interval |
| `<arm>-arm pass count ...` | Cases at or above the threshold, with the chosen interval. Only this line follows `--interval-method` |
| `judge agreement: ...` | A grader with split runs needs its `explanation` and `evidence` read before its verdict is trusted |
| `the result file holds no judge votes ...` | Agreement is unknown, not perfect |

Why score intervals stay normal while the pass count follows the setting:
[local-decisions.md, Interval method](../../methodology/reference/local-decisions.md#interval-method).
How many runs and cases to add when an interval is too wide:
[local-decisions.md, Repeat count](../../methodology/reference/local-decisions.md#repeat-count).

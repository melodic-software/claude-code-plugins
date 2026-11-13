# Reading `aggregate-result.json`

Read when a run has written its JSON, or when a wrapper needs to consume one. This repository reads
the document as the statement of record, never the terminal output. For what a `--json` run prints,
see the `--json` row of
[Command options](https://code.claude.com/docs/en/plugin-evals#command-options) and
[JSON result](https://code.claude.com/docs/en/plugin-evals#json-result).

## Contents

- [Read order](#read-order)
- [Denials](#denials)
- [Document fields](#document-fields)
- [Per-case fields](#per-case-fields)
- [Per-run fields](#per-run-fields)
- [Per-grader fields](#per-grader-fields)
- [What a delta does and does not say](#what-a-delta-does-and-does-not-say)
- [Noise report](#noise-report)
- [Detection control](#detection-control)

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
  expansion or a relative word other than a flag or a command name, or does not parse. A `$NAME`
  or `${NAME}` counts as the value of an earlier `NAME=<literal>` in the same command when that
  assignment is a command of its own that always runs in the top-level shell. A command that
  names no absolute argument, a redirect's file or a prefix assignment's value aside (`ls`,
  `PYTHONPATH=/x pytest`, `cat /x | ls`), also adds no path, unless it is `cat`, `head`, `wc`,
  `grep`, `egrep`, `fgrep` or `sed` reading a pipe. A plain read pipeline of those, `sed` only
  with `-n`, with no opening assignment, names only its absolute file operands, so a
  quoted grep pattern or `-e` value is no path (`grep -E "a|b" /x | head`); a `-f` pattern file
  is a path.
- Up to five kinds of denial are set aside before any other rule judges the run, each a warning that never
  counts toward a FAIL: a named call other than Skill aimed only under the run's own plugin-data
  directory (`<sandbox>/config/plugins/data`), or a compound Bash command one of whose commands is
  aimed only there while every other absolute path it names was named by an allowed Bash call of
  the same run (with no expansion left unresolved). In such a compound, an `echo` with no redirect
  or command substitution names nothing (`rm -f '<data>/f'; echo "rm exit=$?"`). A `Read`, `Grep`
  or `Glob` aimed only under the
  session's own `<sandbox>/config/projects/*/*/tool-results/`, where it reads back output it already
  received. The same plain read pipeline that reads only there is set
  aside the same way, also after opening `NAME=value` commands whose names it expands, where a value
  with a `/` must be a path there and any other value a plain literal such as a pattern or count
  (`F=<saved>; N=40; head -n "$N" "$F"`), after one opening `cd` there whose directory
  relative paths then resolve against (`cd <dir>; sed -n 1,9p <file>`), and as several such
  pipelines joined by `;` or `&&`. Any other Bash call (a redirect, another command, a `||`, `&` or
  subshell, a `cd` with a flag or not first, an assignment to `PATH`, `IFS` or another name that
  changes how the shell or a reader works, an unquoted glob, brace or `$`, or a path outside that
  directory), a write, or any other
  path in the config directory (`settings.json` included) keeps the rules below. The third applies
  only under `--own-copy-search-warns`, which the broken side of a negative control passes: a
  `Read`, `Grep` or `Glob` aimed only at or under the plugin copy the run's init line lists as loaded
  (a `suite.root` or `suite.plugins` path), in a run that finished, when no `tool_used` grader of its
  case names that tool. The gutted skill sends the session searching its own copy for the text it
  lost. Without the flag that denial is a FAIL, since in a normal run it usually means the skill
  references a file it cannot read. A rooted `Glob` pattern or one holding `..`, any other tool,
  and a run that did not finish keep the rules below even with the flag. Compare a run with any of
  these denials only with runs denied the same way. A negative control compares the degraded side
  against a before run that has no such denial, so there a case whose degraded runs carry an
  own-copy search cannot decide the control: its drop must hold with those cases left out.
- The fourth is a with-arm denied compound Bash call whose plugin part a later Bash call in the
  same run ran alone and was allowed: the run shows the plugin call itself permitted, so the
  wrappers drew the denial. Split the denied command at `;`, `&&`, `||` and newlines, drop
  assignment-only commands and `cd`, and, after the plugin part, `ls`, `echo` or `cat` (piped only
  into `head` or `tail`). A command is never dropped when a word of it holds `<` or `>` anywhere,
  quoted or not, other than `2>&1`, `>&2`, `2>&-` or a `/dev/null` target. Exactly one command
  must remain, naming a path at or under the plugin's directory, and a later call with no denial
  must be that command and nothing else, word for word once quotes are removed and same-command
  variables resolved; a word holding a glob, brace, tilde or `$` must match with its quoting too.
  A command holding an unquoted `&`, `(` or `)`, or a `$(` or backtick outside single quotes
  anywhere, never qualifies, nor does a plugin part holding an unquoted glob, brace or tilde or
  an unresolved `$`. A denial whose plugin part never ran alone keeps the rules below.
- The fifth is a denied search, in a without-arm run that finished, whose every term names only a
  `suite.plugins` plugin: in a slash-command case the arm lacks the skill it was asked to run, so
  it may search the disk for it (`find / -ipath '*markdown-format*'`,
  `grep -rIl javascript-format <run home>`). The search is one `find` whose only tests are `-name`,
  `-iname`, `-path` or `-ipath` (with their `!` or `-not` negations, which add no term, and
  `-type`, `-maxdepth`, `-mindepth`, `-a` and `-print`, never `-o`), or one `grep`, `egrep` or `fgrep` with plain flags and `-e` patterns, either
  piped only into `head` or `tail` with no file operand; or a `Grep` pattern, or a `Glob` pattern whose every segment other than `*`
  and `**` names the plugin. A term matches once its `*`, `.`, `^`, `$` and `/` ends are stripped,
  case ignored. Any other command, flag, redirect into a file, unquoted glob or `$`, term, tool,
  a with-arm run, or a run that did not finish keeps the rules below.
- One exception overrides that FAIL: a denial of the same named call other than Skill (tool and
  target) in every run of its case, in both arms, is a warning, with or without an absolute path,
  unless an absolute path it names is at, under or above the plugin's directory. The environment
  denied it with or without the plugin, such as a user-scope read of `~/.claude/standards`. In an
  A/B pass, gate each version's result file.
- Any other denial, in either arm, is a warning only when its case has denial-free runs in that arm
  and its run scored the same as each; otherwise it is a FAIL.
- A with-arm Bash call whose result reports a sandbox network denial, error or not, is a denial
  whose hosts the summary names (the report and its source:
  [SKILL.md, Sources](../SKILL.md#sources), sandbox network denial report). It is a FAIL, since the
  score then measures a blocked request, unless the case is an invocation probe, a control (tagged
  `control`, `no-trigger` or `negative-control`, described as a no-trigger case, or forbidding its
  own skill's call and requiring none), or tagged `no-network`; those set it aside as a warning.
  A without-arm run's network denials are not read, and the report quoted anywhere but a Bash
  result is not a denial.
- A run at 0 turns whose trace holds assistant messages ran a slash-invoked `context: fork` skill
  in a forked session, and the gate lists it under `session started` without failing it. Any run
  fails there whose trace holds a user message with a `local-command-stderr` reading `Shell command
  failed for pattern` (a skill's pre-computed command failed), or a failed Bash result reporting a
  read-only file system at a relative path or under the run's sandbox, in any case: the run's
  workspace or `TMPDIR` was not writable, so the score measures the sandbox, not the skill. A
  read-only path elsewhere is the sandbox working as designed and does not fail the check, nor
  does a relative one in a failed call that only reads absolute paths through those readers,
  joined by `;`, `&&`, `||` or newlines, such as a grep of a saved tool result: it prints the text
  it read. A path under the run's sandbox fails the run whatever the call ran.
- `plugins loaded` fails a with-arm run whose trace init line has a `plugin_errors` entry for a
  `suite.plugins` plugin, or leaves that plugin out of its `plugins` list. That run ran without the
  plugin under test. The detail names the plugin and the error type, such as
  `dependency-unsatisfied`. The check requires a `suite.plugins` path inside a case's directory
  only in that case's runs, treating it as that case's own helper. A with-arm run whose init line
  has no `plugins` list is a warning.
  - **Pointer**: when judging which cases a plugin path loads in, fetch the `plugins` row of
    [prompt.md fields](https://code.claude.com/docs/en/plugin-evals#prompt-md-fields)
    live.
- An invocation probe's denial of a named call other than Skill is a warning when it follows the
  graded Skill call, or the run held a should-not-fire case whose denial-free runs all held; the
  gate prints each probe case's fire counts with and without denials.
- An invocation probe is a case whose `prompt.md` tags include `invocation-probe`, as
  `/skill-quality:check measure-invocation` emits it. Its should-fire misses are the trigger rate
  it measures: `skill fired` reports them as a warning with per-case counts, never a FAIL. Run
  errors and denials keep their full force, apart from the probe exceptions above and a
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
  does **not** by itself imply score 0: some errored runs are still graded, while a run that ended
  on an API error, a rate limit mid-suite included, scores 0 ungraded, which is why that limit reads
  as a regression rather than as an outage. Which runs fall on each side:
  [JSON result](https://code.claude.com/docs/en/plugin-evals#json-result).
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

- For how the delta, a run score and a case score are computed, and when a case passes, read
  [How a case is scored](https://code.claude.com/docs/en/plugin-evals#how-a-case-is-scored) live.
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
  probe pair in [records.md](records.md#spoke-reach). Check the trace for a denied `Read` before
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

## Detection control

A two-version compare that finds no loss means the cut lost nothing only if the suite can see a
loss. Before a cut ships on such a reading, run a detection control: the before text with the
changed rule removed, on the same cases and model, launched together with a before run. The suite
detects a loss when the compare calls a `case drop` or the mean case score falls by 0.15 or more;
merge each version's per-case result files into one first, since the noise report calls no
`case drop` when fewer than 3 cases are scored in both. When it does neither, report the reading as
unable to detect a loss: the cut does not ship on it, whatever the after version scored. Report the
control's before and degraded scores beside the compare. For a whole-plugin rewrite, the
`/playbooks:skill-authoring` reference `rewrite-a-plugin.md` (step 4) adds which part to degrade
and preregistering the control before the first paid run.

A whole-page deletion is proven with a sensitivity control instead, since the before text with that
page removed is the after version itself: replace the page with a plausible but wrong version,
launch it together with a before run, and read it by the same loss test. Every other cut keeps the
detection control.

When the compare is VALID, shows no loss, and goes to a pull request a repository holds for it, end
the comment with the repository's release record for the head it ran, if it defines one. In this
marketplace that is the line `<!-- eval-pair verdict=no-loss validity=VALID head=<sha> -->`:
[Cross-lane PR hold](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/loop-lane/README.md#cross-lane-pr-hold).

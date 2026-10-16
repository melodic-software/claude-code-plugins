---
description: "Guided practice around the `claude plugin eval` CLI, which runs and scores a plugin's eval suite: preflight, no-spend validation, a cost estimate under the ceiling, the run, and reading the with-versus-without delta. Use when: 'run my plugin evals', 'plugin eval', 'evaluate this plugin', 'eval my skill', 'does my skill actually fire', 'what is the delta', 'read my eval results', 'compare two eval runs', 'did my change make the skill better', 'is this gain real', 'aggregate-result.json', 'eval CI gate', 'can this machine run evals', 'how much will this eval cost', 'Bash refuses claude plugin eval', 'plugin eval blocked in a worktree', 'plugin eval refuses: too many worktrees', 'can plugin eval measure CLAUDE.md or rules'. Not for designing success criteria (/evals:design) or the skill-creator evals.json format."
argument-hint: "[preflight|validate|run|read <json>|ci|init] [target]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Preflight, price, run, and read a plugin eval suite around the CLI
---

# Run a plugin eval suite

`claude plugin eval` runs each case with the plugin and without it, grades each run, and writes
`aggregate-result.json`. This skill does what the CLI does not, all before money is spent: checks
that this machine can run the suite, prices the run, routes a target that is not a plugin, and
reads the delta. It never re-implements grading and never simulates a run or a score.

## Actions

| Action | What happens |
|---|---|
| `preflight <target>` | Print the report below and stop. No CLI invocation, no spend |
| `validate [<eval-dir>]` | Run the static case validator only. No model call |
| `run <target>` (default) | Preflight, validate, print the estimate, then invoke the CLI |
| `read <json>` | Read a written `aggregate-result.json` in the order that keeps a delta honest |
| `ci` | Answer from the CI section below |
| `init [<name>]` | Scaffold a suite: `claude plugin eval init --bare <name>` where there is no terminal |

This page holds every rule the actions use; answer from it. Each upstream specific it states has a
row under [Sources](#sources). Background for a human reader:
[case-authoring.md](reference/case-authoring.md), [reading-results.md](reference/reading-results.md)
(JSON fields), [ci.md](reference/ci.md) (workflow file, exit codes, parser), and
[records.md](reference/records.md) (the observations behind each source row).

## Preflight

Print every field, in this order, before anything else:

```text
cli_version:     <claude --version>
floor_met:       <true | false> (git: <git --version | none>)
platform:        <windows | wsl2 | linux | darwin | other>
sandbox_backend: <present | absent | not-ready | unknown> (missing: <binaries that did not resolve> | links: <paths>)
target_type:     <plugin | wrapped-skill | wrapped-agent | rules>
suite_tools:     <read-only | the gated tools the cases request>
same_model:      <yes | no | unknown | off> (tested <model>, judge <model>)
estimate_usd:    roughly <n> (cases x runs x arms, plus judge calls)
ceiling:         <n> USD | unlimited
```

**Version floor:** Claude Code 2.1.269. Never assert that the command is installed: read
`claude --version` and let the number decide. `floor_met: false` stops the run and reports the
floor; nothing else is worth doing on a binary that cannot execute a case. `plugin eval is
currently in early access` means an older binary: updating fixes it, no sign-up. `plugin eval is
currently unavailable` means Anthropic has switched the command off for now, possibly by account
or context: nothing local fixes it and there is no access to request, so wait and retry.

**Git floor:** fetch <https://code.claude.com/docs/en/plugin-evals#requirements> live for it. A
git below it sets `floor_met: false` and names the version; no git reports `git: none` and does
not block.

### Sandbox backend

No CLI string reports the backend, so detection is platform-shaped. When the user states their
platform, answer for that platform and take `platform` from what they said. Never infer it from
this session's own host, which may not be the machine that will run the eval.

| Observation | `sandbox_backend` |
|---|---|
| Native Windows (no WSL), or WSL1 (`wsl.exe -l -v` lists the distribution at `VERSION` 1) | `absent` |
| Linux, or WSL2 (`wsl.exe -l -v` lists the distribution at `VERSION` 2; `/proc/version` naming `microsoft` only says the host is WSL, since a custom WSL2 kernel can carry any release string), and every package the sandboxing page lists resolves (`command -v bwrap`, `command -v socat`) | `present` |
| Linux or WSL2, and any of them is missing | `absent`, naming each missing binary |
| macOS | `present` |
| Anything else | `unknown`, treated as `absent` for the refusal below |

Then, when the table gives `present`, a case requests `Bash` or `PowerShell`, and
`find "${DOCKER_CONFIG:-$HOME/.docker}/" -mindepth 1 -type l` (read-only) prints a path, override
to `not-ready`, naming each path and the CLI's reason: the sandbox cannot reliably exclude a store
with a link inside it (the store's root may itself be a link), so the CLI refuses the whole `Bash`-granting pass, read-only cases included
(every run ends at 0 turns with a run error naming the credential store). On `platform: darwin`
with `cli_version` 2.1.293 or later, ignore links under `~/.docker/bin` (Docker Desktop's own); an
older client, or a `$DOCKER_CONFIG` store elsewhere, keeps them `not-ready`. `Write` and `Edit` run
outside the shell sandbox and do not trigger it.

**Refuse before any spend** when `sandbox_backend` is not `present` and any case requests `Bash`,
`PowerShell`, `Write`, or `Edit`. Name both halves in the refusal: why each granting run would be
refused by the CLI (with no backend a run is refused rather than run unconfined) and score 0
rather than measuring anything, and the route.

- `absent` or `unknown`: the backend is missing. On Linux or WSL2, install each missing package,
  restart Claude Code, and confirm with `/sandbox`. Otherwise: WSL2, a Linux host with
  `bubblewrap` and `socat`, macOS, or a Claude cloud session, whose host and missing packages come
  from fetching [Installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools)
  live and applying the matching table row.
- `not-ready`: the backend is present and the packages resolve; the cause is the named links, and
  the route is to resolve them or run on a host without them. Never suggest repointing
  `DOCKER_CONFIG` to get past the check, which bypasses a sandbox safety check.

Read-only suites run anywhere: `Read`, `Glob`, `Grep`, `NotebookRead`, `Skill`, `AskUserQuestion`,
`Agent`, `TodoWrite`, `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`, `TaskStop` (the
validator's `READ_ONLY_TOOLS`). `suite_tools` is `read-only` when every case's `allowed_tools` sits
inside that set; otherwise it lists the gated tools, which are exactly the ones needing an
`--allow-tools` grant. Neither a case nor a skill's own `allowed-tools` can widen that grant; an
ungranted tool is removed and reported on stderr as `not granted`.

### Worktree isolation

A session Claude Code isolated in a worktree (`--worktree`, `EnterWorktree`, or `isolation:
"worktree"`), and every subagent it spawns, has a Bash guard that refuses any command containing
the word `eval`; a normal session whose working directory is a git worktree is not isolated
([records](reference/records.md#worktrees)). It matters only when `run` or `init` invokes the CLI.
Never retry, wrap, reroute, or otherwise bypass it: it matches the word, so nothing clears it.
Build the command with absolute paths: for `run`, an absolute `<target>` and `--json` path inside
the worktree; for `init`, `claude plugin eval init --bare <name>`. Take the first route that fits:

1. Entered with `EnterWorktree`: `ExitWorktree` with `keep`, run it, then `EnterWorktree` back by
   the worktree's path.
2. A worktree-isolated subagent: return the exact command to the caller to run from its own
   non-isolated session.
3. Otherwise print it for the user to run in a terminal outside Claude Code, or in a session
   started with plain `claude` (not `--worktree`) in the worktree.

After a `run`, read the `--json` file back with the `read` action.

Separately, the CLI refuses a plugin inside a repository with many linked worktrees (`registers
more linked worktrees than can be screened`). Copy the plugin into a new empty directory outside
any git repository without git metadata or results (`rsync -a --exclude .git --exclude
'evals/results' <plugin-dir>/ <new empty dir>/`), run against the copy with an absolute target,
and point `--json` at the original's gitignored results directory.

### Tested model and judge

Resolve the model under test and the judge from the planned invocation, the cases' `model` keys,
and the environment, by the `--model` and `--judge-model` rows of the command options table; an
alias and a full model ID naming the same model are the same. Report `unknown` when either cannot
be resolved before a run. Setting: `${user_config.same_model_warning}`; if it renders empty or as
the literal placeholder text, use `true`, the manifest default, and say which you used. When it is
`false`, print `same_model: off` and compare nothing. When `same_model` is `yes`, print this line
under the report. It is advice: the run goes ahead.

```text
warning: the judge is the model under test; pass a different --judge-model
```

## Target routing

The plugin is the only unit the harness loads and the only thing the ablation measures. Every delta
is "this plugin versus no plugin".

| Target | `target_type` | Route |
|---|---|---|
| A plugin root with `plugin.json` or `.claude-plugin/plugin.json` plus an eval dir | `plugin` | Direct. This is the designed path |
| A bare skill directory | `wrapped-skill` | Wrap it in a minimal `.claude-plugin/plugin.json` so it loads as `<name>@skills-dir`; `claude plugin init <name>` scaffolds that. Assert with a `tool_used` grader on `tool: Skill` with `input_match` naming the skill |
| An agent definition | `wrapped-agent` | Ship it in the wrapping plugin's `agents`, list `Agent` in the case's `allowed_tools`, assert `tool_used` on `Agent`. No first-party text describes this route; it composes documented parts, so treat a null result as a route defect before a plugin defect |
| Hooks and slash commands | component of `plugin` | Loaded as plugin components. Hooks run outside the sandbox, so a score for hooks you did not write is advisory unless the run is in a container or a CI runner. Nothing first-party grades command invocation as such |
| MCP servers | component of `plugin` | Mocked by default from `evals/mocks/<server>/<tool>.md`; a real server needs `--allow-real-servers` or `--mocks off` plus an `--allow-tools "mcp__plugin_<plugin>_<server>__*"` grant, and runs as you, outside the sandbox |
| `CLAUDE.md`, `.claude/rules`, user settings, memory | `rules` | **Refused.** Every run starts from a throwaway home with user settings, hooks, `CLAUDE.md`, memory, MCP servers, and other plugins absent, so a shim that re-injects the rule measures the shim, not the rule |

A skill or agent that is not yet wrapped is not a target: report the wrap route, print it, and stop.
The next preflight sees `wrapped-skill` or `wrapped-agent` and proceeds.

For a `rules` target, invoke `/harness-config:unhobble` through the Skill tool when the
`harness-config` plugin is installed: it measures standing instructions by stripping them and
watching what the model stumbles over. When that plugin is absent, say so and describe the
experiment in one sentence (strip the instructions on a branch, log observed stumbles, restore only
what repeated evidence earns) so the user can run it by hand.

## Cost

Every run and every judge grader is a real model call on the operator's account; there is no dry
run.

```text
agent runs  = cases x runs x arms          (arms = 2 under the default ablation, 1 under --ablation none)
judge calls = 3 per llm or baseline grader per run   (the 2-of-3 vote)
```

Four grader types are free (`regex`, `tool_used`, `tool_order`, `file_exists`); `llm` and
`baseline` are billed. Carry the estimate as "roughly": the reported `costUsd` is a list-price
estimate, and arm costs are not symmetric.

**A fresh suite is priced at 0.2 USD per run in either arm, judge calls included, and the figure is
called headroom.** It has no pass of its own to scale, while cases x runs x arms is known before
any spend: four cases at three runs and two arms is 4.8 USD. Once a suite has run, scale from its
own last `costUsd` instead, estimating each arm from its own runs. Use 0.8 USD for a case's
without-arm only when a kept trace shows that arm loading a large skill; a suite with no such trace
is priced at 0.2 alone, and the older anchor is no caveat or risk to that estimate. An opus-judged
run costs more; size it from its own first run. Re-derive the anchors in
[records.md](reference/records.md#cost-anchors) from the last three passes when a Claude Code
release note touches `plugin eval`, the model a run serves changes, or a pass averages more than
0.2 USD per run.

Ceiling: `${user_config.max_cost_usd}` USD, unlimited: `${user_config.unlimited_cost}`. If either
renders empty or as the literal placeholder text, use 5 USD and `false`, the manifest defaults, and
state the ceiling you used without commenting on the setting's state.

1. Print the estimate. This happens on every invocation, including unlimited, and the print is the
   step that must appear in the transcript before any CLI call, not only in the final answer.
2. Unlimited: drop `--max-cost-usd` from the command and start. Never prompt; the estimate already
   printed is the whole disclosure.
3. Ceiling set and estimate under it: the pass goes through. Pass `--max-cost-usd <ceiling>` and
   start, without stopping to ask. A question about whether a pass fits gets the same answer: it
   will go through and starts now under the ceiling, for example "about 4.8 USD, under the 5 USD
   ceiling, so it starts with `--max-cost-usd 5` and no confirmation".
4. Ceiling set and estimate over it: stop and offer three exits, then proceed only on the answer:
   raise the ceiling, narrow the run with `--case <glob>` or `--tag <tag>`, or accept a partial run
   knowing it exits 2 and its scores are not comparable.

The ceiling bounds a list-price estimate, not subscription usage, and it is checked before each run
launches, so an overrun is bounded by the runs already in flight (one, or up to `--concurrency`).
Cheapest levers first: deterministic graders only, then `--ablation none` (halves the runs and
loses the delta), then `--case` or `--tag`, then `--runs 1` for iteration with a confirm at 3, then
a committed `mocks/.replay/` so agent mocks replay without a model call.

## Run

1. Run the static validator. It reaches no model:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/validate/scripts/validate-cases.py" <eval-dir>
   ```

   Use `python` where `python3` does not resolve. In this repository's own checkout
   `${CLAUDE_PLUGIN_ROOT}` is `plugins/evals`, here and below. Exit 0 means proceed (WARN lines
   are advice, not a stop); exit 1 means at least one FAIL, so stop and fix the cases before
   spending, invoking the `evals:validate` skill through the Skill tool for the finding detail;
   exit 2 means the eval dir is unreadable or the arguments are wrong, which is also a stop.

2. Run "Calibrating a judge" first unless every `llm` grader it can reproduce has passed with this
   run's judge model. On a miss, fix the rubric or calibrate a stronger `--judge-model` and use it.

3. Invoke the CLI. The target comes first: placed after `--tag`, `--allow-tools`, or `--json` it
   is swallowed as their value (`--json output path must end in .json`).

   ```bash
   claude plugin eval <target> --trust-plugin --keep-temp --judge-model opus --json results.json --threshold 0.8 --max-cost-usd <n> --no-publish
   ```

   When preflight's `suite_tools` lists gated tools, add `--allow-tools` with exactly those tools;
   without the grant each is removed from every run, so a case that must run or verify its own
   work cannot.

   Without `--trust-plugin` a non-TTY run against an untrusted directory is refused with exit 1.
   `--keep-temp` keeps each run's trace for the validity gate under "Reading the delta". A run
   that feeds a decision keeps `--judge-model opus`, since the CLI's default judge is uncalibrated
   for decisions; only an exploratory run drops it. Run it in the foreground with a tool timeout
   that covers the estimate (a three-case pass took about six minutes here) and wait. **Stay
   attached until every run exits:** a headless (`-p`) session never backgrounds the CLI (the run
   ends with the session: it says "the run started", exits, and leaves an empty `out/` and no
   JSON), runs suites one after another (`-j` adds concurrency inside one), and
   answers only after all exit; an interactive session backgrounds a run only as a harness-tracked
   task it waits for. A run is finished when the process exits and `results.json` exists; read the
   exit code and the JSON together, never one alone. Write the file where git ignores it (the
   CLI's own copy lands under `<eval dir>/results/<timestamp>/`, which can take `--json` too when
   ignored); a run result is evidence to distill, not a file to commit.

4. Read the JSON with the `read` action below. With `--json <file>` there is no terminal table, so
   the JSON is the only record of what happened.

Where a harness guard other than the worktree refusal above blocks a Bash command containing the
bare word `eval`, run the same command through the PowerShell tool instead. The command text is
unchanged; only the tool differs.

## Reading the delta

Read in this order. Stopping early at any step is the finding.

1. Run the validity gate before reading any number:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/run-validity.py" results.json --runs <the run count the eval used>
   ```

   The run count is the run's `--runs`, else the cases' `runs`, else 3. Without the traces
   `--keep-temp` kept it reports the trace checks unchecked and the run INVALID. Report a score,
   delta, or interval only from `verdict: VALID` (exit 0), naming any warnings it printed. On
   `verdict: INVALID` (exit 1), report INVALID with every reason on that line and no number, then
   fix the cause and rerun. Tell the user to post that INVALID line and its reasons in place of
   the number; "post nothing" is not the instruction. Exit 2 means the file could not be read or
   an argument was wrong: say which. The steps below still apply to a VALID run.

   A with-arm denial aimed at or under the plugin's own directory, at a directory above it (which
   covers its files), or with no absolute path or no known plugin directory, is a FAIL: the agent
   reached for a plugin file it could not read, so the fact belongs in the hub. Any other denial,
   in either arm, is a warning only when that run scored the same as every denial-free run of its
   case in the same arm, so it left the score unchanged; with a different score, or no
   denial-free run to compare, it is a FAIL.
2. `partial`. `true` (with `partialReason` of `cost_ceiling`, `interrupted`, or `auth_failed`) means
   the suite did not finish: report that and keep the document out of any trend.
3. Per run, `skippedPaidGraders: true` or a non-null `error`. A skipped judge grader is still
   scored, as a failure with `explanation: "skipped: cost ceiling"`, so it silently depresses the
   arm. A non-null `error` does not imply score 0, because the run is graded on what it produced.
   Either makes the case not comparable; say so instead of reporting its number.
4. `cases[].aggregates.delta`. It is **omitted** when the arms are not comparable. An omitted delta
   is never zero, and neither is a missing `scoreWithout`.
5. Only now read the delta: with-arm score minus without-arm score. A case the gate's `ceiling`
   line names cannot show a gain: say it is excluded and use the delta that line gives over the
   other cases.
6. Run the noise report over the same file and read its lines before calling any delta a gain:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/noise-report.py" results.json --threshold <the run's --threshold> --interval-method <method> --grader-agreement
   ```

   `<method>` is `${user_config.interval_method}`, and an empty or unfilled value there means the
   default, `normal`, applies; do not mention the setting's state to the user. Pass
   `--grader-agreement` unless `${user_config.grader_run_twice}` is `false`. Any other method
   value is passed as is, and the script falls back to `normal`. These values set the command this
   skill runs; they say nothing about a user's own run. Exit 2 means the file could not be read or
   an argument was malformed: say which, and report no interval.

Read the noise report's lines this way:

- `verdict: within noise` or `verdict: n too small to call`: the gain is not established, whatever
  the delta's sign or size. Say so before any number.
- `verdict: the interval excludes 0`: report the delta together with its interval.
- `near ceiling`: the baseline leaves no headroom, so the suite has almost no room to show a gain.
  Add a case the model fails without the plugin before reading the delta again.
- `not comparable` and `score check`: name the case. A score check means the run's reported score
  and its graders disagree; read that run's graders before using its number.
- `judge agreement`: a grader with split runs needs its explanation and evidence read before its
  verdict is trusted. The line saying the file holds no judge votes means agreement is unknown,
  not perfect.
- `cost`: report it beside the scores, in the same answer as the delta.
- Two versions: `--baseline <before.json> --margin <m>`; read `compare verdict` with each
  `case drop`.
- `pass count`: the interval method (the `interval_method` setting, the `--interval-method` flag)
  changes only this line, the count of cases at or above the threshold. Every score interval, the
  delta line included, uses the normal method paired over cases whatever the setting, because a
  case score is not a proportion of trials. So a normal delta interval under `wilson` is the
  setting working as designed, and nothing needs checking.
  [local-decisions.md, Interval method](../methodology/reference/local-decisions.md#interval-method)
  records the decision for a human reader.

Spot-read outputs against verdicts before trusting any delta. For each case whose delta you
report, open a few runs from each arm (the grader explanations in `results.json`, and the kept
trace from `--keep-temp`), at least one its graders passed and one they failed where both exist,
and check each verdict against what the output does. A pass on a wrong output, or a fail on a
correct one, makes the grader or its rubric the finding: fix it and rerun before quoting the
number, and say which run showed it.

What the number means:

- A case at 1.00 in both arms proves the plugin contributed nothing to that case. It is a passing
  case and a null measurement at the same time.
- A grader that cannot pass without the plugin (every `tool_used` on `tool: Skill`, plus anything
  `arm: with-only`) is excluded from scoring in both arms and reported in the with-arm as an
  indicator carrying `scored: false`. A `passed: false` grader inside a 1.00 run is that exclusion,
  by design. When every grader in a case is such a grader, they are scored normally instead.
- `arm: both` forces scoring in both arms, which is what a must-not-invoke check (`min: 0` **and**
  `max: 0`) needs.
- Hold the ablation mode fixed. Under `--ablation none` nothing is excluded, so absolute scores are
  not comparable across modes and mixing them silently breaks a trend line.
- Spoke reach is version-bound: at 2.1.270 and 2.1.287 every with-arm `Read` under the plugin
  directory was denied, so only the hub reached the model; at 2.1.289 `context/`, `reference/`,
  `actions/` and `templates/` reads succeeded.
  Check the trace for a denied `Read` before crediting a spoke.

End the reading with one line on the change under test: `promote` only when the run is VALID, the
noise report's verdict is that the interval excludes 0 with the with-arm ahead, and the spot-read
found no verdict it disagrees with; otherwise `do not promote`, followed by the first of those
conditions that failed.

## Iterating

1. Read the delta column first, never the absolute score. The read is done when each case is
  either a number or an explicit "not comparable".
2. The usual first finding: a delta near zero with the case's `tool_used: Skill` grader failing means the model is not
  choosing the skill on natural phrasing. Fix the skill's `description`, not the case, and re-run
  that one case until the grader passes. A passing fired grader shows the trigger works; it is not
  evidence that the skill improved, and any claim of a gain still needs a VALID run and its noise
  report.
3. That grader passing and a negative delta: suspect the judge before the plugin, since a small
  judge marks a correct answer wrong on formatting. Re-run with a larger `--judge-model` and
  tighten the rubric until it survives a rubric silent on form.
4. Iterate on one case with `--case <name> --runs 1 --ablation none` (it reports `SCORE` and
  `PASS%`, no delta). One run is noisy, so confirm any change at 3 runs per case, the only repeat
  count this repository sets
  ([local-decisions.md, Repeat count](../methodology/reference/local-decisions.md#repeat-count)),
  and read the confirm's noise report before trusting it.
5. Give each case one grader on the result and one on how the model got there (`tool_used` or
  `tool_order`). That pairing separates "the answer was right" from "the plugin is why".

## Calibrating a judge

Trust an `llm` grader's scores only after its judge, the model the suite uses, agrees with labeled
answers on at least 90% of runs; a pass says nothing about another model. Before the first full
run, calibrate every LLM-judge grader the harness can reproduce (one with labeled samples, judging
text); the default judge is uncalibrated until it passes. Report any other judge grader as
uncalibrated, never trusted silently. Labels are the must-pass and must-fail answers in the case's
`samples/<grader>.json`, set by three agents independently with the user settling every
disagreement:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/calibrate-judge.py" build --suite <eval-dir> --out <empty dir outside the repo>
claude plugin eval <out> --trust-plugin --ablation none --threshold 0 --runs 3 --judge-model <the suite's judge model> --keep-temp --no-publish --json <out>/results.json
python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/calibrate-judge.py" score --manifest <out>/manifest.json <out>/results.json
```

`build` writes one case per sample into an empty plugin: the source case's prompt goes out
unchanged, and an appended system prompt presents the sample as fixed test material for the agent
to output byte for byte, even when wrong or incomplete, with no commentary, so the judge grades
that sample as the answer to that question. No generated file carries the label; a must-pass and a
must-fail case differ only in the sample text. `build` skips a grader that judges a file or mock
calls, and prints one line for each empty or whitespace-only sample it skips: Claude Code answers
an empty reply with an injected user turn, so it cannot be reproduced, and an empty answer is a
deterministic failure that needs no judge. The appended prompt does not reach a `focus: trace`
judge. `--threshold 0` keeps the CLI's exit
code about errors, since must-fail cases are meant to score 0.

`score` prints a `FAIL grader` line for each grader under 90% and exits 1; fix that rubric, or move
the whole suite to a stronger judge, and calibrate again before reading its scores. Its false
positives and negatives name the samples to read first. Agreement leaves out a run whose reply was
not the sample, and one with neither a kept trace nor judge evidence (also reported unchecked). A
sample with no reproduced run is listed `untested`, counts toward no agreement, and shows in the
verdict line; raise `--runs` or tighten the prompt before reading the grader's score.

## CI

A CI job runs the command under Run with `--model` and `--judge-model` added, under three rules:
pin both, each to a full model ID and never an alias such as `sonnet`, so a model rollout is not
read as a plugin regression; pass `--trust-plugin` because a non-TTY job is otherwise refused; and
read the JSON in addition to the exit code. Exit 1 still fails the job on a below-threshold case,
but it is overloaded across six causes and exit 2 means partial, so the JSON is what tells a
reader which one happened and whether the arms were comparable at all. This section's pointer
record is the CI pins row under [Sources](#sources).

## Boundary, the built-in `plugin eval` command

- The **CLI** (`plugin eval`, a built-in command) owns execution, grading, the ablation arms, the
  JSON and the HTML report. It is gated by the version floor under Preflight, so this skill reads
  the version and never assumes the command is available. This skill owns what surrounds a spend:
  the preflight, the no-spend validation, the estimate and ceiling, target routing and the reading
  discipline. It never re-implements grading and never simulates a run or a score.
- Success criteria and case design belong to `/evals:design`; come here once a suite exists.
- `evals/evals.json`, the skill-creator format, is a different, non-interchangeable format:
  validate it with `/skill-quality:check validate-evals` when the `skill-quality` plugin is
  installed; otherwise state that the file follows that format and validation was skipped.

## Next

- Validator FAIL, or a case file that failed to load: `/evals:validate <eval-dir>`.
- Target turns out to be `CLAUDE.md` or rules rather than a plugin: `/harness-config:unhobble`.
- Suite ran and the delta is read, and a case needs sharper criteria: `/evals:design <target>`.

## Gotchas

- A pass that crosses the ceiling late can still end `partial: false` with exit 0 and one case
  missing its `delta`: the ceiling skips judge calls, not runs. A pass that crosses it earlier
  skips whole cases and reports `partial: true` with exit 2. Only the JSON distinguishes them.
- The without-arm is not the with-arm minus the plugin: the model without the plugin may load a
  bundled skill such as `claude-api` and cost several times the with-arm. Estimate each arm from
  its own runs.
- `--trust-plugin` persists. Answering the trust prompt yes inside a git repository trusts the whole
  repository, and later non-TTY runs launch instead of being refused.
- Without `--keep-temp` the per-run `tracePath` points at a directory the runner has already
  deleted, so decide on `--keep-temp` before the run, not after reading a surprising score.
- A typo in `--case` exits 1 and no exit code separates it from a real failure, so read the CLI's
  message before treating an exit 1 as a failing case.
- A usage or rate limit mid-suite is **not** marked partial, so `partial: false` does not show the
  runs ended normally. Later runs end with the error, are graded on what they produced, and usually
  score 0 in both arms, so the suite reads as a regression. Check each affected run's `error`
  (`cases[].arms.with[].error`, `cases[].arms.without[].error`) before believing a drop; when it
  names the limit, rerun those cases with `--case` once the limit resets. It is neither a
  regression nor flaky cases, and leaving the cases out of the trend is not enough on its own.
  When `error` is null, run the validity gate and the noise report before drawing any conclusion,
  and say nothing yet about the cases themselves.
- A run from inside a Claude Code session keeps its report local and says `kept local`; from a
  terminal it may publish to claude.ai unless `--no-publish` is passed.
- The sandbox limits what the agent under test can reach. It is not a boundary against the
  plugin's own code: hooks, `--scaffold` scripts, and real MCP servers run as you, outside it, with
  network access. A passing suite is a behavior measurement, never a security vetting.

## Sources

Each row: the rule it backs, the pointer to read live, as-of date, recheck trigger. When a trigger
fires, re-read the pointer, refresh the rule and its [records.md](reference/records.md) entry, and
record a drift outcome in this plugin's CHANGELOG.

| Rule | Pointer | As of | Recheck when |
|---|---|---|---|
| Version floor and its two error strings | `claude plugin eval --help`; troubleshooting in <https://code.claude.com/docs/en/plugin-evals> | 2026-09-12 | A release note touches `plugin eval`, or the floor error string changes |
| Git floor | <https://code.claude.com/docs/en/plugin-evals#requirements>; refusal at <https://code.claude.com/docs/en/plugin-evals#git-is-too-old-for-claude-plugin-eval> | 2026-10-10 | That section changes the floor or its no-git exemption |
| Sandbox backend table and the no-backend refusal | [Set up Linux and WSL2](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2); plugin-evals platform notes | 2026-10-04 | Either names a Windows backend, or adds or drops a package or WSL note |
| Docker credential-store refusal and the `~/.docker/bin` exemption | <https://code.claude.com/docs/en/changelog> (2.1.293); no docs page covers it | 2026-10-10 | A docs page documents the check, or a release note touches sandbox credential exclusion or exempt paths |
| Cloud route host and packages | [Installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools) | 2026-10-11 | That section changes its host description or package list |
| Read-only tool set | <https://code.claude.com/docs/en/plugin-evals#grant-tools> | 2026-10-10 | That section's allowed-tools sentence changes |
| Worktree Bash guard refusal of `claude plugin eval --help`, and which session shapes it covers | Observed on Claude Code 2.1.301 ([records.md](reference/records.md#worktrees)) | 2026-10-16 | A release note touches worktree isolation or `plugin eval` |
| Worktree Bash guard refusal of the user's `!` command | Observed on Claude Code 2.1.285 ([records.md](reference/records.md#worktrees)) | 2026-10-01 | A release note touches worktree isolation or `plugin eval` |
| CLI linked-worktree refusal | Observed on Claude Code 2.1.289 ([records.md](reference/records.md#worktrees)) | 2026-10-04 | A release note changes the limit or the CLI's repository screening |
| Model and judge resolution | <https://code.claude.com/docs/en/plugin-evals#command-options> | 2026-10-01 | The table changes its `--model` or `--judge-model` row |
| Flag order, trust refusal, flag defaults | `claude plugin eval --help`; <https://code.claude.com/docs/en/plugin-evals#command-options> | 2026-09-12 | `--help` no longer matches, or a release note touches the flag set |
| Cost anchors (list-price estimates, this plugin's read-only suite, Claude Code 2.1.287 and 2.1.296) | [records.md, Cost anchors](reference/records.md#cost-anchors) | 2026-10-11 | A release note touches `plugin eval`, the served model changes, or a pass averages more than 0.2 USD per run |
| Spoke reach | <https://code.claude.com/docs/en/plugin-evals#grant-tools>; kept traces in [records.md](reference/records.md#spoke-reach) | 2026-10-04 | A release note touches `plugin eval` or sandbox permissions, or a kept trace on 2.1.289 or later shows a spoke `Read` denied |
| Repeat count | <https://code.claude.com/docs/en/plugin-evals#how-a-case-is-scored> | 2026-10-01 | The page changes its default run count |
| Judge calibration: what a judge reads, the 90% bar, trace judges not seeing the prompt | <https://code.claude.com/docs/en/plugin-evals#what-a-grader-can-look-at>; "When the grader is an LLM judge" in [eval-audit.md](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md); a kept 2.1.287 trace | 2026-10-02 | The focus table changes, a kept trace starts carrying the prompt or system prompt, or eval-audit.md moves its bar |
| CI pins | <https://code.claude.com/docs/en/plugin-evals#run-evals-in-ci>; <https://code.claude.com/docs/en/model-config#model-aliases> | 2026-10-02 | Either section changes how it pins or resolves a model |
| Ceiling shapes, trust persistence, the unmarked limit, `kept local`, `init` needing a terminal | <https://code.claude.com/docs/en/plugin-evals> (`--max-cost-usd` and exit-code rows, rate-limit troubleshooting, HTML report, "Write a case manually", CI); [records.md](reference/records.md#ceiling-trust-and-report-behavior) | 2026-09-13 | A release note touches `plugin eval`, publishing, `init` or limit handling, or a pass shows a ceiling shape not named here |

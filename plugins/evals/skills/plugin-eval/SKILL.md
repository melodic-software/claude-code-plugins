---
description: "Guided practice around the `claude plugin eval` CLI, which runs and scores a plugin's eval suite: preflight (version floor, sandbox backend, target type), static validation with no model call, a cost estimate under the configured ceiling, the run, and the with-versus-without delta read correctly. Use when: 'run my plugin evals', 'plugin eval', 'evaluate this plugin', 'eval my skill', 'does my skill actually fire', 'what is the delta', 'read my eval results', 'compare two eval runs', 'did my change make the skill better', 'is this gain real', 'aggregate-result.json', 'eval CI gate', 'can this machine run evals', 'how much will this eval cost', 'Bash refuses claude plugin eval', 'plugin eval blocked in a worktree', 'can plugin eval measure CLAUDE.md or rules' (it names the route that can). Not for designing success criteria (use /evals:design) or the skill-creator evals.json format (use /skill-quality:check validate-evals when installed)."
argument-hint: "[preflight|validate|run|read <json>|ci|init] [target]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Preflight, price, run, and read a plugin eval suite around the CLI
---

# Run a plugin eval suite

`claude plugin eval` loads one plugin, runs each case twice (with the plugin and without it), grades
each run, and writes `aggregate-result.json`. It does not check whether this machine can run the
suite, price the run, route a target that is not already a plugin, or teach what the delta means.
That is this skill's job, and every part of it happens before money is spent.

## Actions

| Action | What happens |
|---|---|
| `preflight <target>` | Print the report below and stop. No CLI invocation, no spend |
| `validate [<eval-dir>]` | Run the static case validator only. No model call |
| `run <target>` (default) | Preflight, validate, print the estimate, then invoke the CLI |
| `read <json>` | Read a written `aggregate-result.json` in the order that keeps a delta honest |
| `ci` | Give the CI command and its rules from the CI section below, which answers a CI question by itself; [reference/ci.md](reference/ci.md) holds the full workflow file as background |
| `init [<name>]` | Scaffold a suite: `claude plugin eval init --bare <name>` where there is no terminal |

This page states the rules the run and read steps use; answer from it.
[reference/case-authoring.md](reference/case-authoring.md) (writing cases) and
[reference/reading-results.md](reference/reading-results.md) (the full JSON field list) are
background for a human reader.

## Preflight

Print every field, in this order, before anything else:

```text
cli_version:     <claude --version>
floor_met:       <true | false>
platform:        <windows | wsl2 | linux | darwin | other>
sandbox_backend: <present | absent | unknown>
target_type:     <plugin | wrapped-skill | wrapped-agent | rules>
suite_tools:     <read-only | the gated tools the cases request>
same_model:      <yes | no | unknown | off> (tested <model>, judge <model>)
estimate_usd:    roughly <n> (cases x runs x arms, plus judge calls)
ceiling:         <n> USD | unlimited
```

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| Version floor: the command needs Claude Code 2.1.269 or later; an older binary answers `plugin eval is currently in early access`, which updating Claude Code fixes with no sign-up; `plugin eval is currently unavailable` means Anthropic has the command switched off for now, which can change at any time and may depend on the account or context. Nothing local fixes it and there is no access to request: wait and retry | `claude plugin eval --help` on the floor release plus <https://code.claude.com/docs/en/plugin-evals> troubleshooting, verified 2026-09-12 | Recheck trigger: a Claude Code release note touches `plugin eval`, or the floor error string changes. Then re-run `--help`, re-read the page, refresh this row with the outcome, and record a drift outcome in this plugin's CHANGELOG |

`floor_met: false` stops the run and reports the floor; nothing else in this skill is worth doing on
a binary that cannot execute a case. Never assert that the command is installed: read
`claude --version` and let the number decide.

### Sandbox backend

No CLI string reports the backend, so detection is platform-shaped. When the user states their
platform, answer for that platform and take `platform` from what they said. Never infer it from
this session's own host, which may not be the machine that will run the eval.

| Observation | `sandbox_backend` |
|---|---|
| Native Windows (no WSL) | `absent` |
| `/proc/version` contains `microsoft` (WSL2) | `present` |
| Linux and both `bwrap` and `socat` resolve on PATH | `present` |
| Linux and either is missing | `absent` |
| macOS | `present` |
| Anything else | `unknown`, treated as `absent` for the refusal below |

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| Granting `Bash` puts every command under Claude Code's OS-level sandbox; on a machine with no backend each run is refused rather than run unconfined, so the case reports a run error and usually scores 0. Linux needs `bubblewrap` and `socat`; macOS is supported; native Windows has no backend | <https://code.claude.com/docs/en/plugin-evals> platform notes and <https://code.claude.com/docs/en/sandboxing>, verified 2026-09-12 | Recheck trigger: the page names a Windows backend, or names a new dependency. Then re-read it, re-derive the table above, and refresh this row with the outcome |

**Refuse before any spend** when `sandbox_backend` is not `present` and any case requests `Bash`,
`Write`, or `Edit`. Name both halves in the refusal: the backend is missing, so each granting run
would be refused by the CLI and score 0 rather than measuring anything; and the route is WSL2, a
Linux host with `bubblewrap` and `socat`, macOS, or a Claude cloud session. Read-only suites
(`Read`, `Glob`, `Grep`, `NotebookRead`, `Skill`, `Agent`, `TodoWrite`, the `Task*` tools) are
unaffected and run anywhere.

`suite_tools` is `read-only` when every case's `allowed_tools` sits inside that set; otherwise it
lists the gated tools, which are exactly the ones needing an `--allow-tools` grant. A case cannot
widen the operator grant, and neither can a skill's own `allowed-tools`; an ungranted tool is
removed from the session and reported on stderr as `not granted`.

### Worktree isolation

When the session runs isolated in a git worktree, the Bash guard refuses any command containing the
word `eval`, `claude plugin eval --help` included, and refuses the user's own `!` command in that
session the same way. This applies only when `run` or `init` is about to invoke `claude plugin eval`;
`preflight`, `validate`, `read`, and `ci` never invoke it and proceed as usual. Do not retry, wrap
the command in a script, route it through another tool, or bypass the guard in any other way. Stop,
print the exact command this skill would have run and tell the user to paste it into a terminal
outside Claude Code. For `run` that is `claude plugin eval <target> ...` with an absolute
`<target>` and an absolute `--json` path inside the isolated worktree, so the command gives the same
result from any directory; for `init` it is `claude plugin eval init --bare <name>`, which takes no
`--json`. After a `run`, read the `--json` file back with the `read` action.

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| In a worktree-isolated session the built-in Bash guard refuses any command containing `eval`, including `claude plugin eval --help`, with `this command runs a string through eval, which can't be verified to stay inside the worktree`; the user's own `!` command is refused the same way | melodic-software/claude-code-plugins#5696 repro on Claude Code 2.1.285, Linux/WSL2, verified 2026-10-01 | Recheck trigger: a Claude Code release note touches worktree isolation or `plugin eval`. Then re-run `claude plugin eval --help` from an isolated worktree session and refresh this row with the outcome |

### Tested model and judge

`same_model` compares the model under test with the judge model. Resolve each from the planned
invocation, the cases' `model` keys, and the environment, by the `--model` and `--judge-model`
rows of the command options table; an alias and a full model ID that name the same model count as
the same. Report `unknown` when either cannot be resolved before a run.

Setting: `${user_config.same_model_warning}`. If it renders empty or as the literal placeholder
text, use `true`, the manifest default, and say which you used. When it is `false`, print
`same_model: off` and compare nothing.

When `same_model` is `yes`, print this line under the report. It is advice: the run goes ahead.

```text
warning: the judge is the model under test; pass a different --judge-model
```

- **Pointer**: for how each model is chosen, see
  <https://code.claude.com/docs/en/plugin-evals#command-options>.
- **As of**: 2026-10-01
- **Recheck trigger**: the command options table changes its `--model` or `--judge-model` row.

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
`harness-config` plugin is installed: it owns measuring standing instructions by stripping them and
watching what the model stumbles over. When that plugin is absent, say so and describe the
experiment in one sentence (strip the instructions on a branch, log observed stumbles, restore only
what repeated evidence earns) so the user can run it by hand.

## Cost

Every run and every judge grader is a real model call on the operator's account. There is no free
mode and no dry run.

```text
agent runs  = cases x runs x arms          (arms = 2 under the default ablation, 1 under --ablation none)
judge calls = 3 per llm or baseline grader per run   (the 2-of-3 vote)
```

Four grader types are free (`regex`, `tool_used`, `tool_order`, `file_exists`); `llm` and `baseline`
are billed. Carry the estimate as "roughly": the reported `costUsd` is a list-price estimate, and
arm costs are not symmetric.

Sizing anchors, measured on this plugin's own read-only suite at Claude Code 2.1.287 on 2026-10-02,
with no `--model` (it served opus-5-5): 24 runs (four cases, three runs, two arms, sonnet judge)
cost 1.67 USD, 16 runs (two runs, haiku judge) 0.98 USD, and 42 short single-arm calibration runs
1.79 USD: 0.04 to 0.07 USD per run on average, judge calls included, 0.03 to 0.17 USD for one run.

**A fresh suite is priced at 0.1 USD per run in either arm, judge calls included, and the figure is
called headroom.** It has no pass of its own to scale, while cases x runs x arms is known before any
spend. 0.1 USD is 1.4 to 2.4 times the per-run cost of each pass above, and prices six cases at
three runs and two arms at 3.6 USD. Once a suite has run, scale from its own last `costUsd` instead.

The older anchor of 0.8 USD per without-run, which prices the same six cases at about 16 USD, comes
from passes at 2.1.270 (2026-09-12 and 2026-09-13) whose without-arm loaded the bundled `claude-api`
skill and cost five to seven times the with-arm. At 2.1.287 no without-run loaded a skill, and that
arm cost less than the with-arm. Estimate each arm from its own runs, and use 0.8 for a case only
when a kept trace shows its without-arm loading a large skill. A suite with no such trace is priced
at 0.1 alone, and the older anchor is no caveat or risk to that estimate. Re-derive these anchors
from the last three passes when a Claude Code release note touches `plugin eval`, the model a run
serves changes, or a pass averages more than 0.1 USD per run.

Ceiling: `${user_config.max_cost_usd}` USD, unlimited: `${user_config.unlimited_cost}`. If either
renders empty or as the literal placeholder text, use 5 USD and `false`, the manifest defaults, and
state the ceiling you used without commenting on the setting's state.

1. Print the estimate. This happens on every invocation, including unlimited, and the print is the
   step that must appear in the transcript before any CLI call.
2. Unlimited: drop `--max-cost-usd` from the command and start. Never prompt; the estimate already
   printed is the whole disclosure.
3. Ceiling set and estimate under it: the pass goes through. Pass `--max-cost-usd <ceiling>` and
   start, without stopping to ask. A question about whether a pass fits gets the same answer: it
   will go through and starts now under the ceiling, for example "about 3.6 USD, under the 5 USD
   ceiling, so it starts with `--max-cost-usd 5` and no confirmation".
4. Ceiling set and estimate over it: stop and offer three exits, then proceed only on the answer:
   raise the ceiling, narrow the run with `--case <glob>` or `--tag <tag>`, or accept a partial run
   knowing it exits 2 and its scores are not comparable.

The ceiling bounds a list-price estimate, not subscription usage, and it is checked before each run
launches, so an overrun is bounded by the runs already in flight (one, or up to `--concurrency`).
Cheapest levers first: deterministic graders only, then `--ablation none` (halves the runs and loses
the delta), then `--case` or `--tag`, then `--runs 1` for iteration with a confirm at 3, then a
committed `mocks/.replay/` so agent mocks replay without a model call.

## Run

1. Run the static validator. It reaches no model:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/validate/scripts/validate-cases.py" <eval-dir>
   ```

   Use `python` where `python3` does not resolve. In this repository's own checkout that script is
   `plugins/evals/skills/validate/scripts/validate-cases.py`. Exit 0 means proceed (WARN lines are
   advice, not a stop); exit 1 means at least one FAIL, so stop and fix the cases before spending,
   invoking the `evals:validate` skill through the Skill tool for the finding detail; exit 2 means
   the eval dir is unreadable or the arguments are wrong, which is also a stop.

2. Invoke the CLI. Confirm the target comes first, before any list-taking flag:

   ```bash
   claude plugin eval <target> --trust-plugin --keep-temp --json results.json --threshold 0.8 --max-cost-usd <n> --no-publish
   ```

   `--keep-temp` keeps each run's trace, which the validity gate under "Reading the delta" reads.

   Run it in the foreground with a tool timeout that covers the estimate (a three-case pass took
   about six minutes here) and wait. Never background the CLI from a headless `-p` session: the
   session ends and takes the run with it.

   The run is finished when the process exits and `results.json` exists; read the exit code and the
   JSON together, never one alone. Write the file somewhere git ignores (the CLI's own copy lands
   under `<eval dir>/results/<timestamp>/`, and a repo that ignores that tree can take `--json`
   there too); a run result is evidence to distill, not a file to commit.

3. Read the JSON with the `read` action below. With `--json <file>` there is no terminal table, so
   the JSON is the only record of what happened.

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| The target must precede `--tag`, `--allow-tools`, and `--json` or it is swallowed as their value (`--json output path must end in .json`). `--trust-plugin` asserts trust and skips the first-run prompt, and a non-TTY run against an untrusted directory is refused exit 1 without it. `--keep-temp` preserves the per-run trace directories the runner otherwise deletes. `--judge-model` defaults to a small fast model (haiku); `--model` pins the agent under test; `-j/--concurrency` takes 1 to 8 and cuts wall-clock only; `--threshold` defaults to 1.0 | `claude plugin eval --help` plus <https://code.claude.com/docs/en/plugin-evals>, verified 2026-09-12, with the arg-order and trust behavior reproduced against this repository's suite | Recheck trigger: `--help` no longer matches a row, or a release note touches the flag set. Then re-run `--help`, re-derive the row, refresh this record with the outcome, and land a drift outcome in this plugin's CHANGELOG |

Where a harness guard other than the worktree refusal above blocks a Bash command containing the
bare word `eval`, run the same command through the PowerShell tool instead. The command text is
unchanged; only the tool differs.

## Reading the delta

Read in this order. Stopping early at any step is the finding.

1. Run the validity gate before reading any number:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/run-validity.py" results.json --runs <the run count the eval used>
   ```

   The run count is the run's `--runs`, else the cases' `runs`, else 3. In this repository's
   checkout the script is `plugins/evals/skills/plugin-eval/scripts/run-validity.py`. It needs the
   traces `--keep-temp` kept; without them it reports the trace checks unchecked and the run
   INVALID. Report a score, delta, or interval only from `verdict: VALID` (exit 0), naming any
   warnings it printed. On `verdict: INVALID` (exit 1), report INVALID with every reason on that
   line and no number, then fix the cause and rerun. Tell the user to post that INVALID line and
   its reasons in place of the number; "post nothing" is not the instruction. Exit 2 means the file could not be read or an
   argument was wrong: say which. The steps below still apply to a VALID run.

   A with-arm denial aimed at or under the plugin's own directory, at a directory above it (which
   covers its files), or with no absolute path or no known plugin directory, is a FAIL: the agent reached for a plugin file it could not
   read, so the fact belongs in the hub. Any other denial, in
   either arm, is a warning only when that run scored the same as every denial-free run of its case
   in the same arm, so it left the score unchanged; with a different score, or no denial-free run to
   compare, it is a FAIL.
2. `partial`. `true` (with `partialReason` of `cost_ceiling`, `interrupted`, or `auth_failed`) means
   the suite did not finish: report that and keep the document out of any trend.
3. Per run, `skippedPaidGraders: true` or a non-null `error`. A skipped judge grader is still scored,
   as a failure with `explanation: "skipped: cost ceiling"`, so it silently depresses the arm. A
   non-null `error` does not imply score 0, because the run is graded on what it produced. Either
   makes the case not comparable; say so instead of reporting its number.
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
   default, `normal`, applies; do not mention the setting's state to the user. Pass `--grader-agreement` unless `${user_config.grader_run_twice}`
   is `false`. Any other method value is passed as is, and the script falls back to `normal`. These
   values set the command this skill runs; they say nothing about a user's own run. In
   this repository's checkout the script is `plugins/evals/skills/plugin-eval/scripts/noise-report.py`.
   Exit 2 means the file could not be read or an argument was malformed: say which, and report no
   interval.

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
- `pass count`: the interval method (the `interval_method` setting, the `--interval-method` flag)
  changes only this line, the count of cases at or above the threshold. Every score interval, the
  delta line included, uses the normal method paired over cases whatever the setting, because a
  case score is not a proportion of trials. So a normal delta interval under `wilson` is the
  setting working as designed, and nothing needs checking.
  [local-decisions.md, Interval method](../methodology/reference/local-decisions.md#interval-method)
  records the decision for a human reader.

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
- The with-arm measures the skill hub, not its spokes. A plugin whose value lives in `reference/`
  files measures only what `SKILL.md` carries, and no grant makes the spokes readable (record
  below). So anything a case depends on goes in the hub, and a null delta on such a plugin is a hub
  finding before it is a plugin finding.

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| In the with-arm the injected skill body names the plugin's real on-disk directory, and a `Read` of any file under it is refused with `File is in a directory that is denied by your permission settings`; only the hub `SKILL.md` text reaches the model. A path-scoped `--allow-tools "Read(//<plugin>/skills/**)"` grant is accepted but does not lift the denial, and no flag makes a directory readable | Kept traces (`--keep-temp`) of this plugin's own suite: at Claude Code 2.1.270, six with-arm runs, every spoke `Read` denied, verified 2026-09-13; at 2.1.287 under `--runs 2`, all three spoke `Read` calls in six with-arm runs denied with that text and listed in each trace's `permission_denials`, verified 2026-10-01; at 2.1.287 with that grant on one case, both with-arm runs still denied a spoke `Read` and the run's settings held no deny rule, and `claude plugin eval --help` listed no readable-directory flag, verified 2026-10-02. For what a grant covers, see <https://code.claude.com/docs/en/plugin-evals#grant-tools>, as of 2026-10-02 | Recheck trigger: a Claude Code release note touches `plugin eval` or sandbox permissions, `--help` or that section gains a way to make a directory readable, or a kept trace shows a spoke `Read` succeeding. Then re-run one case with `--keep-temp`, with and without the grant, read the with-arm trace, refresh this row with the outcome, and record a drift outcome in this plugin's CHANGELOG |

## Iterating

1. Read the delta column first, never the absolute score. The read is done when each case is either
   a number or an explicit "not comparable".
2. The usual first finding is a delta near zero with the case's `tool_used: Skill` grader failing:
   the model is not choosing the skill on natural phrasing. Fix the skill's `description`, not the
   case, and confirm by re-running that one case until the grader passes. A passing fired grader
   shows the trigger works; it is not evidence that the skill improved, and any claim of a gain
   still needs a VALID run and its noise report.
3. If that grader passes and the delta is negative, suspect the judge before the plugin. A small
   judge marks a correct answer wrong on formatting. Re-run with a larger `--judge-model` and
   tighten the rubric so formatting cannot decide the verdict; the step is settled when the verdict
   survives a rubric that says nothing about form.
4. Iterate on one case with `--case <name> --runs 1 --ablation none`, which reports `SCORE` and
   `PASS%` instead of `WITH`, `W/OUT`, and delta. One run is noisy, so confirm any change at 3
   runs per case and read the confirm's noise report before trusting it.
5. Give each case one grader on the result and one on how the model got there (`tool_used` or
   `tool_order`). That pairing is what separates "the answer was right" from "the plugin is why".

3 runs per case is the confirm level; this repository sets no other repeat count.

- **Pointer**: for how runs make up a case score, see
  <https://code.claude.com/docs/en/plugin-evals#how-a-case-is-scored>; for this repository's
  repeat-count decision, see
  [local-decisions.md, Repeat count](../methodology/reference/local-decisions.md#repeat-count).
- **As of**: 2026-10-01
- **Recheck trigger**: the plugin-evals page changes its default run count.

## Calibrating a judge

Trust an `llm` grader's scores only after its judge agrees with labeled answers on at least 90% of
runs. The labels are the must-pass and must-fail answers in the case's `samples/<grader>.json`;
three agents label them independently and the user settles every disagreement. Then:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/calibrate-judge.py" build --suite <eval-dir> --out <empty dir outside the repo>
claude plugin eval <out> --trust-plugin --ablation none --threshold 0 --runs 3 --judge-model <the suite's judge model> --keep-temp --no-publish --json <out>/results.json
python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/calibrate-judge.py" score --manifest <out>/manifest.json <out>/results.json
```

`build` writes one case per sample into an empty plugin: the source case's prompt goes out
unchanged, and an appended system prompt has the agent reply with the sample word for word, so the
judge grades that sample as the answer to that question. No generated file carries the label; a
must-pass and a must-fail case differ only in the sample text. The appended prompt presents the
sample as fixed test material to output byte for byte even when it is wrong or incomplete, with no
commentary added. `build` skips a grader that judges a file or mock calls, and prints one line for
each empty or whitespace-only sample it skips: Claude Code answers an empty reply with an injected
user turn, so it cannot be reproduced, and an empty answer is a deterministic failure that needs no
judge. `--threshold 0` keeps the CLI's exit code about errors, since must-fail cases are
meant to score 0. Calibrate with the judge model the real suite uses; the result says nothing
about another.

`score` prints a `FAIL grader` line for each grader under 90% and exits 1; fix that rubric, or move
to a stronger judge, and calibrate again before reading its scores. Its false positives and
negatives name the samples to read first. A run whose reply was not the sample is left out of the
agreement, and so is one with neither a kept trace nor judge evidence, which is also reported
unchecked. A sample with no reproduced run is listed as `untested`, counts toward no agreement,
and shows in the verdict line; raise `--runs` or tighten the prompt before reading the grader's score.

- **Pointer**: what a judge reads for each `focus`, see
  <https://code.claude.com/docs/en/plugin-evals#what-a-grader-can-look-at>; the 90% bar, see
  "When the grader is an LLM judge" in
  [eval-audit.md](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md).
  A kept trace of a Claude Code 2.1.287 run held neither the case prompt nor any system prompt
  text, so the appended instruction does not reach a `focus: trace` judge.
- **As of**: 2026-10-02
- **Recheck trigger**: the focus table changes, a kept trace starts carrying the prompt or system
  prompt, or eval-audit.md moves its agreement bar.

## CI

A CI job runs the command under Run with `--model <full model ID>` and
`--judge-model <full model ID>` added, under these three rules: pin both `--model` and `--judge-model` so a model rollout
is not read as a plugin regression, pass `--trust-plugin` because a non-TTY job is otherwise refused,
and read the JSON in addition to the exit code. The CLI's own exit 1 still fails the job on a
below-threshold case, but it is overloaded across six causes and exit 2 means partial, so the JSON
is what tells a reader which one happened and whether the arms were comparable at all.

A CI pin is a full model ID for each of the two, never an alias such as `sonnet`.

Answer a CI question from this section. [reference/ci.md](reference/ci.md) has the full workflow
file, the exit-code table, and the parser rules as background for a human reader.

- **Pointer**: for the CI invocation and its model pins, see
  <https://code.claude.com/docs/en/plugin-evals#run-evals-in-ci>; for what an alias resolves to,
  see <https://code.claude.com/docs/en/model-config#model-aliases>.
- **As of**: 2026-10-02
- **Recheck trigger**: either section changes how it pins or resolves a model, or the command
  options table changes its `--model` or `--judge-model` row.

## Boundary, the built-in `plugin eval` command

- The **CLI** (`plugin eval`, a built-in command) owns execution, grading, the ablation arms, the
  JSON, and the HTML report. It is gated: below the version floor recorded in the preflight
  section it refuses to run, so this skill reads the version and never assumes the command is
  available. This skill
  owns what surrounds a spend: the preflight, the no-spend validation, the estimate and ceiling,
  target routing, and the reading discipline. It never re-implements grading and never simulates a
  run or a score.
- **Success criteria and case design** belong to `/evals:design`, which interviews for measurable
  criteria before any case exists. Come here once a suite exists.
- **`evals/evals.json`**, the skill-creator format, is a different and non-interchangeable format:
  validate it with `/skill-quality:check validate-evals` when the `skill-quality` plugin is
  installed; otherwise state that the file follows that format and validation was skipped.
- **`CLAUDE.md` and rules** are out of scope by construction, per the routing table above.

## Next

- Validator FAIL, or a case file that failed to load: `/evals:validate <eval-dir>`.
- Target turns out to be `CLAUDE.md` or rules rather than a plugin: `/harness-config:unhobble`.
- Suite ran and the delta is read, and a case needs sharper criteria: `/evals:design <target>`.

## Gotchas

- The worktree refusal says the command runs a string through eval, but `claude plugin eval` does
  not; the guard matches the word `eval`, so no flag or rewording of the command clears it.
- A pass that crosses the ceiling can still end `partial: false` with exit 0 and one case missing
  its `delta`: the ceiling skips judge calls, not runs. A pass that crosses it earlier skips whole
  cases and reports `partial: true` with exit 2. Only the JSON distinguishes them.
- The without-arm is not the with-arm minus the plugin. At Claude Code 2.1.270, on a knowledge case
  it cost four to seven times as much (at 2.1.287 it cost less; see Cost): the kept traces show
  the model without the plugin invoking the bundled `claude-api` skill on every run, and that
  skill's injected body is about fourteen times the size of this plugin's hub.
- Inside the with-arm, a `Read` of the plugin's own `reference/` files is refused, so the spokes
  never reach the model; see the record under "Reading the delta" before crediting a spoke.
- `--trust-plugin` persists. Answering the trust prompt yes inside a git repository trusts the whole
  repository, and later non-TTY runs launch instead of being refused.
- `--json <file>` suppresses the terminal summary table. Without `--keep-temp` the per-run
  `tracePath` points at a directory the runner has already deleted, so decide on `--keep-temp`
  before the run, not after reading a surprising score.
- A `-p` session that backgrounds the CLI call answers "the run started" and exits, and the run
  dies with it: one temp directory with an empty `out/`, no JSON, no results directory. Observed
  on this plugin's own suite, verified 2026-09-13; recheck when a release note touches headless
  tool execution.
- A headless `-p` session tends to go from the reads straight to the CLI call and print the
  estimate in its final answer. The estimate step above says before; when the transcript is the
  evidence, read it for the order, not only for the number.
- A typo in `--case` exits 1 and no exit code separates it from a real failure, so read the CLI's
  message before treating an exit 1 as a failing case. [reference/ci.md](reference/ci.md#exit-codes)
  records the message for a human reader.
- A usage or rate limit mid-suite is **not** marked partial, so `partial: false` does not show the
  runs ended normally. Later runs end with the error, are graded on what they produced, and usually
  score 0 in both arms, so the suite reads as a regression. Check each affected run's `error`
  (`cases[].arms.with[].error` and `cases[].arms.without[].error`) before believing a drop; when it
  names the limit, rerun those cases with `--case` once the limit resets. It is neither a regression
  nor flaky cases, and leaving the cases out of the trend is not enough on its own. When `error` is
  null, run the validity gate and the noise report under "Reading the delta" before drawing any
  conclusion, and say nothing yet about the cases themselves.
- A run from inside a Claude Code session keeps its report local and says `kept local`; from a
  terminal it may publish to claude.ai unless `--no-publish` is passed.
- The sandbox limits what the agent under test can reach. It is not a boundary against the plugin's
  own code: hooks, `--scaffold` scripts, and real MCP servers run as you, outside it, with network
  access. A passing suite is a behavior measurement, never a security vetting.
- `claude plugin eval init` needs a terminal. Use `init --bare <name>` anywhere there is none; it
  reaches no model call.

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| The ceiling's two shapes (`partial: false` with exit 0 and a missing `delta` when it is crossed late, `partial: true` with exit 2 when it is crossed early), `--trust-plugin` persisting across later runs in the same repository, and `--json <file>` suppressing the terminal summary table | Reproduced across this pilot's five passes at Claude Code 2.1.269 and 2.1.270 and recorded in [`docs/specs/plugin-evals-pilot-measurement.md`](https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/plugin-evals-pilot-measurement.md), "Observations for the runner skill", verified 2026-09-12, against the `--max-cost-usd` and exit-code rows of <https://code.claude.com/docs/en/plugin-evals> | Recheck trigger: a release note touches `plugin eval`, or a pass reports a ceiling shape this row does not name. Then re-read the page, re-run one ceilinged pass, refresh this row with the outcome, and record a drift outcome in this plugin's CHANGELOG |
| A usage or rate limit mid-suite is not marked partial; a run a Claude Code session started keeps its report local and says `kept local`, while a terminal run publishes unless `--no-publish` is passed; `init` needs a terminal and `init --bare <name>` runs nothing | <https://code.claude.com/docs/en/plugin-evals>, its troubleshooting entry for a usage or rate limit, its HTML-report section, and its "Write a case manually" and CI sections, verified 2026-09-13 | Recheck trigger: a release note touches report publishing, `init`, or limit handling, or one of these sections no longer reads this way. Then re-read the page, re-derive this row, and refresh this record with the outcome |

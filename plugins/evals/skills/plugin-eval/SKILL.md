---
description: "Guided practice around the `claude plugin eval` CLI, which runs and scores a plugin's eval suite. This skill does the rest: preflight (version floor, sandbox backend, target type), static validation with no model call, a printed cost estimate under the configured ceiling, the run itself, and the with-versus-without delta read correctly. Use when: 'run my plugin evals', 'plugin eval', 'evaluate this plugin', 'eval my skill', 'does my skill actually fire', 'what is the delta', 'read my eval results', 'aggregate-result.json', 'eval CI gate', 'can this machine run evals', 'how much will this eval cost'. Not for designing success criteria (use /evals:design), not for the skill-creator evals.json format (use /skill-quality:check validate-evals when the skill-quality plugin is installed), and not for CLAUDE.md or rules, which every run strips."
argument-hint: "[preflight | validate | run | read <json> | ci | init] [target]"
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
| `ci` | Emit the CI recipe and the parser rules from [reference/ci.md](reference/ci.md) |
| `init [<name>]` | Scaffold a suite: `claude plugin eval init --bare <name>` where there is no terminal |

Case authoring belongs to [reference/case-authoring.md](reference/case-authoring.md); the JSON field
list belongs to [reference/reading-results.md](reference/reading-results.md). Read the one the
current step needs, not both.

## Preflight

Print every field, in this order, before anything else:

```text
cli_version:     <claude --version>
floor_met:       <true | false>
platform:        <windows | wsl2 | linux | darwin | other>
sandbox_backend: <present | absent | unknown>
target_type:     <plugin | wrapped-skill | wrapped-agent | rules>
suite_tools:     <read-only | the gated tools the cases request>
estimate_usd:    roughly <n> (cases x runs x arms, plus judge calls)
ceiling:         <n> USD | unlimited
```

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| Version floor: the command needs Claude Code 2.1.269 or later; an older binary answers `plugin eval is currently in early access`, and a server-side switch answers `plugin eval is currently unavailable`, which nothing local restores | `claude plugin eval --help` on the floor release plus <https://code.claude.com/docs/en/plugin-evals> troubleshooting, verified 2026-09-12 | Recheck trigger: a Claude Code release note touches `plugin eval`, or the floor error string changes. Then re-run `--help`, re-read the page, refresh this row with the outcome, and record a drift outcome in this plugin's CHANGELOG |

`floor_met: false` stops the run and reports the floor; nothing else in this skill is worth doing on
a binary that cannot execute a case. Never assert that the command is installed: read
`claude --version` and let the number decide.

### Sandbox backend

No CLI string reports the backend, so detection is platform-shaped:

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

For a `rules` target, invoke `/claude-config:unhobble` through the Skill tool when the
`claude-config` plugin is installed: it owns measuring standing instructions by stripping them and
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

Sizing anchors, measured on this plugin's own read-only suite (three cases, three runs, two arms,
default models, 2026-09-12): about 0.10 USD per with-run, 0.70 to 0.82 USD per without-run on a
knowledge case, about 0.002 USD of judge calls per run, 2.1 to 2.7 USD for a full pass. **Estimate
the without-arm from its own anchor, not from the with-arm**: without the plugin the model spends
turns hunting, and here that arm cost seven times the with-arm. Absent a probe, size a without-run
at 0.8 USD and say the figure is headroom.

Ceiling: `${user_config.max_cost_usd}` USD, unlimited: `${user_config.unlimited_cost}`. If either
renders empty or as the literal placeholder text, use 5 USD and `false`, the manifest defaults, and
say which you used.

1. Print the estimate. This happens on every invocation, including unlimited, and the print is the
   step that must appear in the transcript before any CLI call.
2. Unlimited: drop `--max-cost-usd` from the command and start. Never prompt; the estimate already
   printed is the whole disclosure.
3. Ceiling set and estimate under it: pass `--max-cost-usd <ceiling>` and start.
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
   claude plugin eval <target> --trust-plugin --json results.json --threshold 0.8 --max-cost-usd <n> --no-publish
   ```

   The run is finished when the process exits and `results.json` exists; read the exit code and the
   JSON together, never one alone.

3. Read the JSON with the `read` action below. With `--json <file>` there is no terminal table, so
   the JSON is the only record of what happened.

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| The target must precede `--tag`, `--allow-tools`, and `--json` or it is swallowed as their value (`--json output path must end in .json`). `--trust-plugin` asserts trust and skips the first-run prompt, and a non-TTY run against an untrusted directory is refused exit 1 without it. `--keep-temp` preserves the per-run trace directories the runner otherwise deletes. `--judge-model` defaults to a small fast model (haiku); `--model` pins the agent under test; `-j/--concurrency` takes 1 to 8 and cuts wall-clock only; `--threshold` defaults to 1.0 | `claude plugin eval --help` plus <https://code.claude.com/docs/en/plugin-evals>, verified 2026-09-12, with the arg-order and trust behavior reproduced against this repository's suite | Recheck trigger: `--help` no longer matches a row, or a release note touches the flag set. Then re-run `--help`, re-derive the row, refresh this record with the outcome, and land a drift outcome in this plugin's CHANGELOG |

Where a harness guard refuses a Bash command containing the bare word `eval`, run the same command
through the PowerShell tool instead. The command text is unchanged; only the tool differs.

## Reading the delta

Read in this order. Stopping early at any step is the finding.

1. `partial`. `true` (with `partialReason` of `cost_ceiling`, `interrupted`, or `auth_failed`) means
   the suite did not finish: report that and keep the document out of any trend.
2. Per run, `skippedPaidGraders: true` or a non-null `error`. A skipped judge grader is still scored,
   as a failure with `explanation: "skipped: cost ceiling"`, so it silently depresses the arm. A
   non-null `error` does not imply score 0, because the run is graded on what it produced. Either
   makes the case not comparable; say so instead of reporting its number.
3. `cases[].aggregates.delta`. It is **omitted** when the arms are not comparable. An omitted delta
   is never zero, and neither is a missing `scoreWithout`.
4. Only now read the delta: with-arm score minus without-arm score.

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

## Iterating

1. Read the delta column first, never the absolute score. The read is done when each case is either
   a number or an explicit "not comparable".
2. The usual first finding is a delta near zero with the case's `tool_used: Skill` grader failing:
   the model is not choosing the skill on natural phrasing. Fix the skill's `description`, not the
   case, and confirm by re-running that one case until the grader passes.
3. If that grader passes and the delta is negative, suspect the judge before the plugin. A small
   judge marks a correct answer wrong on formatting. Re-run with a larger `--judge-model` and
   tighten the rubric so formatting cannot decide the verdict; the step is settled when the verdict
   survives a rubric that says nothing about form.
4. Iterate on one case with `--case <name> --runs 1 --ablation none`, which reports `SCORE` and
   `PASS%` instead of `WITH`, `W/OUT`, and delta. One run is noisy, so confirm any change at the
   default three runs before trusting it.
5. Give each case one grader on the result and one on how the model got there (`tool_used` or
   `tool_order`). That pairing is what separates "the answer was right" from "the plugin is why".

## CI

The recipe, its exit-code table, and the parser rules live in [reference/ci.md](reference/ci.md).
Three rules matter enough to state here: pin both `--model` and `--judge-model` so a model rollout
is not read as a plugin regression, pass `--trust-plugin` because a non-TTY job is otherwise refused,
and read the JSON in addition to the exit code. The CLI's own exit 1 still fails the job on a
below-threshold case, but it is overloaded across six causes and exit 2 means partial, so the JSON
is what tells a reader which one happened and whether the arms were comparable at all.

## Boundary

- The **CLI** owns execution, grading, the ablation arms, the JSON, and the HTML report. This skill
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
- Target turns out to be `CLAUDE.md` or rules rather than a plugin: `/claude-config:unhobble`.
- Suite ran and the delta is read: `/evals:design <target>` to sharpen the criteria a case grades.

## Gotchas

- A pass that crosses the ceiling can still end `partial: false` with exit 0 and one case missing
  its `delta`: the ceiling skips judge calls, not runs. A pass that crosses it earlier skips whole
  cases and reports `partial: true` with exit 2. Only the JSON distinguishes them.
- The without-arm is not the with-arm minus the plugin. On a knowledge case it cost seven times as
  much, because the model without the plugin spends turns hunting.
- `--trust-plugin` persists. Answering the trust prompt yes inside a git repository trusts the whole
  repository, and later non-TTY runs launch instead of being refused.
- `--json <file>` suppresses the terminal summary table. Without `--keep-temp` the per-run
  `tracePath` points at a directory the runner has already deleted, so decide on `--keep-temp`
  before the run, not after reading a surprising score.
- A typo in `--case` exits 1 with `No eval cases found matching --case "<glob>"`, which is
  indistinguishable by exit code from a real failure.
- A usage or rate limit mid-suite is **not** marked partial. Later runs end with the error, are
  graded on what they produced, and usually score 0, so the suite reads as a regression. Check
  `cases[].arms.with[].error` before believing a drop.
- A run from inside a Claude Code session keeps its report local and says `kept local`; from a
  terminal it may publish to claude.ai unless `--no-publish` is passed.
- The sandbox limits what the agent under test can reach. It is not a boundary against the plugin's
  own code: hooks, `--scaffold` scripts, and real MCP servers run as you, outside it, with network
  access. A passing suite is a behavior measurement, never a security vetting.
- `claude plugin eval init` needs a terminal. Use `init --bare <name>` anywhere there is none; it
  reaches no model call.

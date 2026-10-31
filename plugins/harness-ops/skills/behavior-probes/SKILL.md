---
description: "Live probes of Claude Code permission, auto-mode, hook, worktree, subagent and sandbox behavior as cases with paired controls, each reported pass, fail or inconclusive with the Claude Code version; dry run by default, live runs opt-in and capped. Use when: 'rerun the behavior probes', 'does auto mode still deny this', 'add a probe case', 'which probes does this release touch'."
argument-hint: "[validate|dry-run|live [--case <id>]...|recheck <range>|add <area>/<name>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Run data-driven live probes of Claude Code permission and platform behavior and record the outcomes
---

## Purpose

Our conventions rest on platform behavior no doc settles: whether a hook `allow` skips the auto-mode
classifier, what an ask rule becomes under `claude -p`, where `EnterWorktree` stops asking. This skill
holds each such behavior as a case and reruns it on demand, so a recheck is one command instead of a
bespoke script. Outcomes are recorded in [records.md](records.md).

`claude plugin eval` cannot carry these cases: a case there cannot set permission rules, `autoMode`, a
permission mode or project settings, and its runs remove ungranted tools instead of deciding them.
**Pointer**: when that question comes up again, fetch <https://code.claude.com/docs/en/plugin-evals>
live. **As of**: 2026-10-08. **Recheck trigger**: a release note adding per-case settings or
permission mode to plugin eval.

The runner is a script bundled here rather than a plugin `bin/` executable, because some surfaces
refuse a plugin with a top-level `bin/`. **Pointer**: when deciding whether this plugin can ship a
`bin/`, fetch <https://code.claude.com/docs/en/plugins/components#executables> live. **As of**:
2026-10-08. **Recheck trigger**: that section stops naming surfaces that refuse a `bin/`.

## Actions

`<probe>` is `python3 "${CLAUDE_SKILL_DIR}/scripts/probe.py"`.

| Action | Command | Cost |
|---|---|---|
| `validate` | `<probe> validate` | none |
| `dry-run` (default) | `<probe> run --dry-run` | none: scaffolds run, `claude` is replaced by a fake |
| `live` | `<probe> run --live [--case <id>]... [--area <area>]... [--retries 1]` | real model runs, capped |
| `recheck` | `<probe> recheck --changelog <file> --range <A..B>` | none |
| `table` | `<probe> table <results.jsonl>` | none |
| `rejudge` | `<probe> rejudge --out <dir of a live run>` | none: re-reads the saved streams after an `expect.json` fix; a verdict-only case keeps its row |

Run `live` only when the user asks for a live run in this turn. Before it, state how many cases it
selects and the ceilings in force (`--max-runs`, `--max-cost-usd`, each case's `max_budget_usd`); a
case past a ceiling is reported `skipped`, never run, and each case's budget is cut to what the suite
ceiling leaves. For what a run costs, point at
[Manage costs](https://code.claude.com/docs/en/costs#track-your-costs).

Each live case runs in its own temp directory with `--setting-sources project,local`, the case's
`settings.json` as `--settings`, its permission mode, its tool lists as `--allowedTools` and
`--disallowedTools` when it sets them, a driver system prompt that keeps the model attempting the
call, and a child environment stripped of this session's variables. Results go to a temp directory
the run prints; the raw stream of each run lands under its `raw/` and never enters the repository. A
verdict-only case saves no stream, and its row carries the verdict and the Claude Code version but no
tool output.

The `lane-permissions` area runs the CI write lane's tool lists under `dontAsk`: five cases check that
its Read deny rules keep Grep, Glob and Read out of `/proc/*/environ` and the checkout's `.git`, and
two controls Grep and Read a file inside the checkout. Its cases are verdict-only, because a failed
deny can return process environment or git config. The lists live once, in
`cases/lib/lane-write-tools.json`, copied from this marketplace repository's `collect-base-activity`
action; when the lane's lists change, change that file.

The `intake-permissions` area runs under `dontAsk` with only `Bash(gh issue view *)` allowed, the
rule shape a read-only issue lane grants. A control runs a plain `gh issue view 1`, and four cases
expect a deny when `;`, `&&`, `|` or `$()` adds a `touch` the rule does not approve. Each case's
settings put a stub `gh` first on `PATH` that logs its arguments and prints `gh-stub-marker`, so a
call that gets through touches no real issue; the control passes only on that marker.

The `autocompact` area checks which auto-compact window `/autocompact`, run with no argument, reports
when a project settings file, the `--autocompact` flag and the environment variable each set one. Its
cases judge the printed line, not a tool call. A base case sets only the project file's top-level
window, and each other case adds one element to a case it names as its control. No case passes
`/autocompact` an argument, which would save to the operator's user settings. Under `claude -p` the
command prints the window with no model turn: a `<synthetic>` assistant message and a result with
`num_turns` 0, which the verdict reads as printed output (record 16). A model answer reads as
`inconclusive`.

The `cloud-routine` area checks state a cloud scheduled task (routine) keeps between runs. Its case
uses `/schedule` to create a one-off task on this marketplace repository, starts one run at once and
lets the scheduled fire be the second. Each run posts an issue comment on #8991, marked with an id the
scaffold writes. The case then polls for 35 minutes at most and judges a final read of the second
run's comment. Each live run creates a routine on the operator's account and posts two public
comments as the operator's GitHub login. The one-off turns itself off after it fires and stays on
the account; delete it from its menu at [claude.ai/code/routines](https://claude.ai/code/routines).
The case is `explicit`, so a live run that does not name it with `--case` skips it. `gh` must be on
`PATH` and signed in, through its config under `HOME`, to an account that can read the issue: the
child environment drops `GH_TOKEN` and the keyring's session variables. The comments also record the date and zone
each run sees, for the date-zone question tracked in #7679 (record 19).

## Reading a result

| Verdict | Meaning | Do |
|---|---|---|
| `pass` | The target call's outcome matched `expect.json` | Refresh the case's row in records.md with the date and version |
| `fail` | It did not | Platform behavior moved. Update the record and every convention that cites it |
| `inconclusive` | The model never attempted the call or made fewer than the case's `count`, a `prints` case's command printed nothing, the CLI did not start, or a case's control did not pass or did not run | Rerun with `--retries 1`; never read it as pass or fail |
| `error` | The scaffold or case is broken | Fix the case; a fixture failure says nothing about the platform |
| `skipped` | Platform, a missing tool, or a ceiling | Report it |

Exit codes: 0 all passed, 1 a fail or error, 3 inconclusive or skipped with no failure.

## Adding a case

A case is `cases/<area>/<name>/` with `settings.json` (`{}` when the case needs none), `prompt.md`,
`expect.json` and an optional `scaffold.sh`. `${PROBE_WORKDIR}` and `${PROBE_CASE_DIR}` are
substituted in `settings.json` and `prompt.md`; a scaffold gets them, plus `PROBE_LIB` (`cases/lib/`)
and `PROBE_MODEL` (the model the case runs), as environment variables and runs in the temp directory.

`expect.json` fields: `claim`; `tags` (terms a changelog item would use for the surface, read by
`recheck`); `target` (`tool`, `input_match` regex over the call's JSON input, `example` input for the
dry run, optional `in_subagent`, `select` of `first|any|all`, `count`); `outcome` (`allow`, `deny`,
`ran` or `refused`: `allow` accepts `ran` or `refused`, `refused` is an error result with no
permission denial); optional `reason_type` (the denial's `decision_reason_type`) and `match` (a
case-insensitive substring of the denial reason or tool result); optional `permission_mode`, `cwd`,
`env`, `max_turns`, `max_budget_usd`, `model`, `platforms`, `requires`; optional `timeout` (seconds,
in place of the run's `--timeout`); optional `explicit` (`true` on a case with effects outside its
temp directory: a live run skips it unless `--case` names it); optional `allowed_tools` and
`disallowed_tools` (lists of permission rules, no rule holding a comma, `${PROBE_WORKDIR}`
substituted) or `tool_rules` (a JSON file in `cases/lib/` holding both lists, for cases that share
them; a list the case sets itself wins); optional `verdict_only` (`true` on a case whose failure would
return a secret: the run saves no stream and no tool output); optional `cli_args` (flag-value
pairs, each flag and value of a shape the runner's `CLI_FLAGS` allows). Outcome `prints` judges what
a slash command in `prompt.md` prints instead of a tool call: its `target` holds `text_match`, a
regex over the first non-blank printed line, `example`, the text the dry run prints, and optional
`printed_match`, a regex a line must match to be judged at all (else `inconclusive`). A `deny` or `refused`
case names its positive control in `control`, a case that differs only in the element that causes the
denial, per the [liveness-assertion convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/liveness-assertion/README.md).
A `prints` case may name a `prints` control whose `example` its `text_match` rejects; either kind
keeps a `pass` only while its control passes.
Run `validate` and `dry-run`, then a live run of the new case and its control, and add its record.

## Next

/harness-ops:changelog diff, to find the release behind a `fail`.

## Gotchas

- The user `CLAUDE.md`, auto memory and the account's connectors still load under
  `--setting-sources project,local`; the driver prompt exists because a `CLAUDE.md` made the model
  refuse before the permission layer was asked.
- A model rewrite such as `git -C <dir> push` escapes a literal `input_match` and a literal permission
  rule alike. Prompts ask for the command character for character, and a rewrite reads as
  inconclusive.
- Which stream carries the authoritative denial record: fetch
  <https://code.claude.com/docs/en/agent-sdk/typescript#sdkpermissiondeniedmessage> live. **As of**:
  2026-10-11. **Recheck trigger**: that section stops naming `permission_denials` on the result
  message as the authoritative record. A denial seen only in `result.permission_denials` reports
  `reason_type` `unknown`.

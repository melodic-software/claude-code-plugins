---
description: "Runs live probes of Claude Code permission, auto-mode, hook, worktree, subagent and sandbox behavior as cases with paired controls; reports pass, fail or inconclusive per case with the Claude Code version. Dry run by default; live runs are opt-in and capped. Use when: 'probe claude code behavior', 'rerun the behavior probes', 'does auto mode still deny this', 'add a probe case', 'which probes does this release touch'."
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
| `rejudge` | `<probe> rejudge --out <dir of a live run>` | none: re-reads the saved streams after an `expect.json` fix |

Run `live` only when the user asks for a live run in this turn. Before it, state how many cases it
selects and the ceilings in force (`--max-runs`, `--max-cost-usd`, each case's `max_budget_usd`); a
case past a ceiling is reported `skipped`, never run, and each case's budget is cut to what the suite
ceiling leaves. For what a run costs, point at
[Manage costs](https://code.claude.com/docs/en/costs#track-your-costs).

Each live case runs in its own temp directory with `--setting-sources project,local`, the case's
`settings.json` as `--settings`, its permission mode, a driver system prompt that keeps the model
attempting the call, and a child environment stripped of this session's variables. Results go to a
temp directory the run prints; the raw stream of each run lands under its `raw/` and never enters the
repository.

## Reading a result

| Verdict | Meaning | Do |
|---|---|---|
| `pass` | The target call's outcome matched `expect.json` | Refresh the case's row in records.md with the date and version |
| `fail` | It did not | Platform behavior moved. Update the record and every convention that cites it |
| `inconclusive` | The model never attempted the call or made fewer than the case's `count`, the CLI did not start, or a negative case's control did not pass or did not run | Rerun with `--retries 1`; never read it as pass or fail |
| `error` | The scaffold or case is broken | Fix the case; a fixture failure says nothing about the platform |
| `skipped` | Platform, a missing tool, or a ceiling | Report it |

Exit codes: 0 all passed, 1 a fail or error, 3 inconclusive or skipped with no failure.

## Adding a case

A case is `cases/<area>/<name>/` with `settings.json` (`{}` when the case needs none), `prompt.md`,
`expect.json` and an optional `scaffold.sh`. `${PROBE_WORKDIR}` and `${PROBE_CASE_DIR}` are
substituted in `settings.json` and `prompt.md`; a scaffold gets them, plus `PROBE_LIB` (`cases/lib/`),
as environment variables and runs in the temp directory.

`expect.json` fields: `claim`; `tags` (terms a changelog item would use for the surface, read by
`recheck`); `target` (`tool`, `input_match` regex over the call's JSON input, `example` input for the
dry run, optional `in_subagent`, `select` of `first|any|all`, `count`); `outcome` (`allow`, `deny`,
`ran` or `refused`: `allow` accepts `ran` or `refused`, `refused` is an error result with no
permission denial); optional `reason_type` (the denial's `decision_reason_type`) and `match` (a
case-insensitive substring of the denial reason or tool result); optional `permission_mode`, `cwd`,
`env`, `max_turns`, `max_budget_usd`, `model`, `platforms`, `requires`. A `deny` or `refused` case
names its positive control in `control`, a case that differs only in the element that causes the
denial, per the [liveness-assertion convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/liveness-assertion/README.md).
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
- `system/permission_denied` events are best-effort; `result.permission_denials` is authoritative. A
  denial seen only there reports `reason_type` `unknown`.

---
description: "Hands a task, investigation or review to OpenAI's Codex CLI as a background job and reads back its jobs. Use when the user asks for Codex: 'ask Codex', 'have Codex do X', 'Codex second opinion', 'Codex review of this branch', 'resume the Codex thread', 'is the Codex job done', 'cancel the Codex run', 'is Codex ready', 'update codex'. A multi-reviewer panel is /review:council."
argument-hint: "[run <prompt>|review --base <ref>|status [<job>]|result <job>|cancel <job>|update]"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(external-agents run codex:*)"
  - "Bash(external-agents review codex:*)"
  - "Bash(external-agents status:*)"
  - "Bash(external-agents result:*)"
  - "Bash(external-agents cancel:*)"
  - "Bash(external-agents update codex:*)"
shell: bash
metadata:
  workflow-stage: implement
  summary: Hand tasks, investigations and reviews to the Codex CLI and read back its jobs
---

# Codex

**Arguments.** `[run <prompt>|review --base <ref>|status [<job>]|result <job>|cancel <job>|update]`.
A bare request that is not one of the other actions is `run`.

This skill drives the plugin's `external-agents` command, which is on the Bash `PATH` while the
plugin is enabled. The command is the only thing that starts Codex; never call `codex` yourself,
and never look up the plugin's install path. Delegate only when the user asks for Codex.

## Actions

| Action | Command | Read |
|---|---|---|
| `run` (default): a task (may write) or an investigation (read-only) | `external-agents run codex --use task\|investigate --prompt-file <file>` | [reference/run.md](reference/run.md) |
| `review`: Codex reviews this branch, read-only | `external-agents review codex --base <ref> [--brief-file <file>]` | [reference/run.md](reference/run.md#review) |
| `status`, `result`, `cancel` | `external-agents status [<job>]`, `result <job>`, `cancel <job>` | [reference/jobs.md](reference/jobs.md) |
| `update`: readiness, CLI facts, version and routing check | `external-agents update codex` | [reference/update.md](reference/update.md) |
| Choosing a model or effort | `--model`, `--effort` for one run; config keys otherwise | [reference/routing.md](reference/routing.md) |

## Reporting a run

- **First reply line:** `Mode: <mode> (<use>)`, taken from the job, never from what was asked: the
  `mode:` line of `external-agents status <job>` (the job id is the `job: <id>` line on stderr).
  A review is always `Mode: read-only (review)`. When the mode ceiling lowered a write request, say
  so and name the config key the notice names. When the run passed `--model` or `--effort`, add
  the `model:` and `effort:` lines from the same status output and why they were chosen.
- Then the command's first stdout line, then Codex's final message verbatim. That message is
  Codex's answer, not yours: relay it, and add your own reading only below it, labeled as yours.
- Exit codes (`scripts/lib/runner.mjs:12`): `0` ok, `1` failed, `2` usage or refused, `3` blocked
  by the mode, `4` Codex unavailable or skipped. On `1`, `2` or `4`, report the first line and the
  CLI's error and stop: never do the task yourself in Codex's place. On `4`, point the user to
  `external-agents update codex`.

## Prompts

Write the prompt with the Write tool to a file in a gitignored scratch folder (this repository's
convention, else the session scratchpad) and pass it with `--prompt-file`; the command keeps its
own copy in the job folder. Name the files and paths Codex should read; never paste file contents,
diffs or logs into the prompt. Codex reads them itself inside its sandbox.

## Background runs

Run every `run` and `review` with the Bash tool's `run_in_background`: a run can last up to
`codex.timeout_seconds`, longer than a foreground Bash call may wait, and a call cut off by its own
timeout leaves the job without its result. You are notified when it exits, so do not poll. The job id prints only at the end, so while it runs, find it with bare
`external-agents status`. Stop a run with `external-agents cancel <job>`, which stops Codex's whole
process tree; stopping the background Bash task alone may leave Codex running.

## Next

`/review:council` for a ranked, multi-reviewer review of the same change, with Codex as one member.

## Gotchas

- **`blocked-by-mode` is not success.** The command records a run `blocked-by-mode`, exits `3`,
  and still prints the final message whenever the sandbox refused a command, whatever Codex's own
  exit was; that message may describe work that never happened. Say the run was blocked, give the
  blocked count and commands from the first line, and never report the task done.
- **A review can be blocked and still count as `ran`.** `codex: ran (...)` with a blocked-commands
  part means Codex tried something the read-only sandbox refused; the findings stand, and the
  blocked part is worth one line in the reply.
- **The ceiling is Codex's sandbox only.** What Codex config can run outside that sandbox is
  upstream's to state: read
  [Non-interactive mode § Permissions and safety](https://learn.chatgpt.com/docs/non-interactive-mode#permissions-and-safety)
  when it matters. The command prints a `notice:` when the reviewed change touches `.codex/`;
  relay that notice.
- **The mode is a ceiling, not a request.** `--mode write` on a use whose configured mode is
  read-only runs read-only; the notice names `codex.uses.<use>.mode`. Only the user changes that
  key, in `<home>/external-agents.yaml` or `.local.yaml`.
- **The breaker refuses runs after an unavailable-class failure** (missing binary, logged out,
  usage limit) until the time it prints. `external-agents update codex` closes it once Codex is
  logged in again; do not retry the run in a loop.
- **`codex.binary_path` is read only from an untracked personal file**
  (`<home>/external-agents.local.yaml`, absolute path, file named `codex`, or `codex.exe`, `.cmd` or `.bat` on Windows). Set anywhere else, it
  is ignored with a `notice: config:` line; relay that notice rather than working around it.
- **Plugin data directory.** Job files, logs, the breaker and the CLI-facts cache live in this
  plugin's data directory, which the command works out for itself; never pass or set
  `CLAUDE_PLUGIN_DATA`. A `notice:` saying another plugin's `CLAUDE_PLUGIN_DATA` is not used is
  expected. A checkout that is not installed refuses to run until `CLAUDE_PLUGIN_DATA` names a
  directory starting with `external-agents-` (see the plugin README's Job files section).
- **CLI flags come from the CLI.** When a question turns on what a Codex flag or subcommand does,
  read the help `update` captured (its `cli facts:` line), not this skill and not memory.

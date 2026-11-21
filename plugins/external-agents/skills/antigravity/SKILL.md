---
description: "Hands a task, investigation or review to Google's Antigravity CLI (agy, Gemini models) and reads back its jobs. Use when the user asks for Gemini or Antigravity: 'ask Gemini', 'have Gemini do X', 'Gemini second opinion', 'Antigravity review of this branch', 'run this through agy', 'is the Gemini job done', 'cancel the agy run', 'is agy ready', 'update antigravity'. A multi-reviewer panel is /review:council."
argument-hint: "[run <prompt>|review --base <ref>|status [<job>]|result <job>|cancel <job>|update]"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(external-agents run antigravity:*)"
  - "Bash(external-agents review antigravity:*)"
  - "Bash(external-agents status:*)"
  - "Bash(external-agents result:*)"
  - "Bash(external-agents cancel:*)"
  - "Bash(external-agents update antigravity:*)"
shell: bash
metadata:
  workflow-stage: implement
  summary: Hand tasks, investigations and reviews to the Antigravity CLI and read back its jobs
---

# Antigravity

**Arguments.** `[run <prompt>|review --base <ref>|status [<job>]|result <job>|cancel <job>|update]`.
A bare request that is not one of the other actions is `run`.

This skill drives the plugin's `external-agents` command, which is on the Bash `PATH` while the
plugin is enabled. The command is the only thing that starts agy; never call `agy` yourself, and
never look up the plugin's install path. Delegate only when the user asks for Gemini or
Antigravity.

## Actions

| Action | Command | Read |
|---|---|---|
| `run` (default): a task (may write) or an investigation (read-only) | `external-agents run antigravity --use task\|investigate --prompt-file <file>` | [reference/run.md](reference/run.md) |
| `review`: agy reviews this branch, read-only | `external-agents review antigravity --base <ref> [--brief-file <file>]` | [reference/run.md](reference/run.md#review) |
| `status`, `result`, `cancel` | `external-agents status [<job>]`, `result <job>`, `cancel <job>` | [reference/jobs.md](reference/jobs.md) |
| `update`: readiness, CLI facts, version and routing check | `external-agents update antigravity` | [reference/update.md](reference/update.md) |
| Choosing a model or effort | none: config keys only | [reference/routing.md](reference/routing.md) |

## Reporting a run

- **First reply line:** `Mode: <mode> (<use>)`, taken from the job, never from what was asked: the
  `mode:` line of `external-agents status <job>` (the job id is the `job: <id>` line on stderr).
  A review is always `Mode: read-only (review)`. When the mode ceiling lowered a write request, say
  so and name the config key the notice names.
- Then the command's first stdout line, then agy's final message verbatim. That message is agy's
  answer, not yours: relay it, and add your own reading only below it, labeled as yours.
- Exit codes (`scripts/lib/runner.mjs:12`): `0` ok, `1` failed, `2` usage or refused, `3` blocked
  by the mode, `4` agy unavailable or skipped. On `1`, `2` or `4`, report the first line and the
  CLI's error and stop: never do the task yourself in agy's place. On `4`, point the user to
  `external-agents update antigravity`.

## Prompts

Write the prompt with the Write tool to a file in a gitignored scratch folder (this repository's
convention, else the session scratchpad) and pass it with `--prompt-file`; the command keeps its
own copy in the job folder. Name the files and paths agy should read; never paste file contents,
diffs or logs into the prompt. For an investigation, name the paths: a read-only agy run reads
files by path and cannot search or list directories.

## Background runs

Run the same command with the Bash tool's `run_in_background`; you are notified when it exits, so
do not poll. The job id prints only at the end, so while it runs, find it with bare
`external-agents status`. Stop a run with `external-agents cancel <job>`, which stops agy's whole
process tree; stopping the background Bash task alone may leave agy running.

## Next

`/review:council` for a ranked, multi-reviewer review of the same change, with agy as one member.

## Gotchas

- **Write is opt-in.** Every use runs read-only until the user sets
  `antigravity.uses.task.mode: write` in `<home>/external-agents.yaml` or `.local.yaml`, because
  agy's write mode has no network isolation (next gotchas). A task asked for while the ceiling is
  read-only runs read-only; relay the notice naming that key, and never set it yourself.
- **A refused action makes the run `blocked-by-mode`, even with a full answer.** agy keeps going
  after a refusal and may still answer well; the command records the run `blocked-by-mode`, exits
  `3` and prints the answer. Relay the answer, name the refused actions from the first line, and
  never report a task done.
- **A write task's limit is agy's sandbox plus agy's own review.** `--mode auto` keeps commands
  in agy's terminal sandbox, but its review lets commands it judges safe and reversible run outside
  it ([Terminal sandbox](https://antigravity.google/docs/sandbox/)). Sandboxed commands have no
  network by default, but a write task on WSL (agy 1.5.14) reached the internet with and without
  `--sandbox`, so treat write mode as having network access. Never ask agy to push, open or
  merge pull requests, or run `gh` or `az`; Claude Code stays the only actor for those.
- **Check the work, not the warning.** agy may print `--mode auto is not available ...;
  continuing in the default mode` (relayed as a `notice:`) and still run in auto mode, writes
  included. Before reporting a task done, check that its files exist; trust neither the notice nor
  the exit code alone.
- **On Windows, auto-mode commands cannot write files** (`EPERM`, observed on agy 1.5.14, also
  with an added directory), so a build or test that writes output fails there. For those, run
  from WSL.
- **Workspace configuration from the branch loads into agy.** agy reads hooks from
  `.agents/hooks.json` in the workspace ([Hooks](https://antigravity.google/docs/hooks/)), plus
  the user's `~/.gemini/config/hooks.json` and installed agy plugins. The command prints a
  `notice:` when a reviewed change touches `.agents/`; relay it before the findings.
- **The breaker refuses runs after an unavailable-class failure** until the time it prints.
  `external-agents update antigravity` closes it once agy is ready again; do not retry in a loop.
- **`antigravity.binary_path` is read only from an untracked personal file**
  (`<home>/external-agents.local.yaml`, absolute path, file named `agy`, or `agy.exe` on
  Windows). Set anywhere else, it is ignored with a `notice: config:` line; relay that notice.
- **Plugin data directory.** Job files, logs, the breaker and the CLI-facts cache live in this
  plugin's data directory, which the command works out for itself; never pass or set
  `CLAUDE_PLUGIN_DATA`. A `notice:` saying another plugin's `CLAUDE_PLUGIN_DATA` is not used is
  expected. A checkout that is not installed refuses to run until `CLAUDE_PLUGIN_DATA` names a
  directory starting with `external-agents-` (see the plugin README's Job files section).
- **CLI flags come from the CLI.** When a question turns on what an agy flag or subcommand does,
  read the help `update` captured (`agy.txt` in its `cli facts:` folder), not this skill and not
  memory.

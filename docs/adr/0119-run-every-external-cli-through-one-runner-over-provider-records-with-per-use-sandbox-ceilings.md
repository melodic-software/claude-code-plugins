# Run every external CLI through one runner over provider records, with per-use sandbox ceilings

- Status: accepted
- Date: 2026-11-21
- Refs: [#17954](https://github.com/melodic-software/claude-code-plugins/pull/17954) (runner, Codex
  record), [#17967](https://github.com/melodic-software/claude-code-plugins/pull/17967) (Antigravity
  record and its defaults); owner interview of 2026-11-20 and 2026-11-21 (Q20, Q31, Q42, Q51, Q59,
  Q64, and "Opt-in write");
  [ADR 0117](0117-replace-the-official-codex-plugin-with-one-external-agents-plugin-and-a-skill-per-cli.md)

## Context

The plugin hands work to CLIs that run in the user's repositories, with the user's credentials,
outside Claude Code's permission system. Each CLI enforces its own limits differently. A Codex run
whose writes were refused still exits 0. A run of agy (the Antigravity CLI) can fall back to
another mode and say so only in a notice. The owner asked for "the safest yet extensible and
configurable method".

## Decision

1. **Provider records are data, and one runner is the only code that starts a CLI.** Each CLI's
   argv, modes, output shape, resume arguments, review kind and denial rules live in
   `providers/<product>.yaml`, checked against one schema that rejects unknown keys. The runner in
   `scripts/lib/runner.mjs` reads the record. It records every job in its own file (command, CLI
   version, exit, duration, status) and keeps the newest 50 per repository.
2. **Each use runs in a sandbox mode, and the configured mode is both its default and its ceiling.**
   Review and investigate are read-only. Task is write for Codex. For agy, task is read-only by
   default, and write is one line in a personal or team file (`antigravity.uses.task.mode`, shipped
   in #17967). The mode is passed on every run, resume included, with no approval prompt and no
   escalation path, and a bypass flag is never passed. A request above the ceiling runs at the
   ceiling, and the reply names the config key. Prompts never carry file contents.
3. **Exit 0 is not success.** A run is `ok` only when the CLI exits 0, its output shows a completed
   turn and no error, its final message is non-empty, and none of its commands or writes was
   denied. Any denial makes the run `blocked-by-mode`, even when the CLI then answers another way.
   The answer still prints.
4. **Per-CLI limits are stated, not implied.**
   - Codex: the sandbox is the only boundary. MCP servers and hooks configured in the repository
     under review run outside it. The runner counts their calls and warns when the branch changes
     `.codex/`.
   - agy: the boundary is agy's sandbox plus agy's own review of commands. Write mode has no network
     isolation. Read-only mode leaves agy only its file-reading tool. No mode restricts web access,
     by owner decision.
5. **A repository never chooses what runs.** `<product>.binary_path` is honored only from an
   untracked personal file, only as an absolute path, and only when the file name is the CLI's own.
6. **Job and breaker files stay in this plugin's data folder.** That folder is the caller's,
   then the installed copy's own, then `CLAUDE_PLUGIN_DATA` only when the name is
   `external-agents-*`, because the Bash environment can carry another plugin's value.
7. **Config lives in `external-agents.yaml` on the config-cascade layers.** These are the plugin
   default, userConfig, the team file and the personal `.local` file. Nothing is kept under
   `~/.claude`, and no model or flag is pinned. With no model configured, the runner passes none,
   and the CLI runs on its own default model (agy included, by owner decision of 2026-11-21).

## Considered options

- **A runner per CLI.** Rejected: each would carry its own success rule, retention and breaker, and
  the safety rules would drift between them.
- **A Bash runner.** Rejected (design T4): the shared libraries are `.mjs`, and one Node file runs
  on Windows and POSIX alike.
- **Exit code alone as success.** Rejected: probes showed refused writes exiting 0.
- **Mark an agy run `ok` when it recovers from a denied command.** Rejected: a recovered run read as
  blocked still shows its answer, while a blocked run read as done hides lost work.
- **An escalation opt-in (`--approve-for-me` or a config flag).** Rejected (Q31, Q59): no escalation
  without a configured ceiling, and none was configured.
- **agy write by default, or agy's hard-wall sandbox setting.** Rejected: write mode has no network
  isolation, so the owner made write opt-in. The hard wall hides user-local toolchains such as mise
  and nvm (Q64).
- **`binary_path` from any config layer.** Rejected (security gate): a committed file in a reviewed
  branch could pick the executable.

## Consequences

- An agy investigate run that tries one shell command ends with exit 3 and `blocked-by-mode`, even
  when its answer is right.
- Codex flag drift is fixed in a record, not in code. `update` re-reads help when the CLI version
  changes.
- A user who wants agy to write sets one config line and accepts that write mode has no network
  isolation.

## Revisit triggers

- Codex starts exiting non-zero on sandbox denials, so exit code could carry success.
- agy gains network isolation in write mode, or a sandbox that keeps user-local toolchains.
- Codex runs repository MCP servers and hooks inside its sandbox.

---
name: setup
description: "Validate the bug-report output configuration and explain how to change it through Claude Code's plugin configuration prompt. Use when: 'set up bug-report', 'configure bug-report', 'bug-report setup', 'where do bug reports land', or you want --file reports committed alongside code."
argument-hint: "(no arguments — interactive validation)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Confirm where `/bug-report:write --file` writes reports without editing Claude Code settings.
`output_dir` is a personal `userConfig` value. Claude Code prompts for it when the plugin is
enabled, stores non-sensitive options in user settings, and ignores `pluginConfigs` entries in
project and local settings on current releases.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## Task

1. Read the rendered `${user_config.output_dir}` value from this skill. Do not inspect or edit
   `settings.json`, `settings.local.json`, managed settings, or `pluginConfigs` directly.
2. Explain the effective behavior:
   - empty or unexpanded value: `--file` uses
     `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`;
   - configured value: `--file` uses that directory.
3. Ask whether reports should remain private to this machine or land in a repository path. For a
   repository path, inspect the consumer's `CLAUDE.md`, `AGENTS.md`, and existing report or
   artifact directories before recommending a portable location. Never recommend a machine-absolute
   team path.
4. If the desired value differs, direct the user to Claude Code's plugin configuration prompt for
   `bug-report`. Claude Code owns persistence. Do not hand-edit any `pluginConfigs` key.
5. Tell the user to rerun this setup after reconfiguration, then verify and report the effective
   destination.

## Output

Report the current effective destination, the recommended destination, and whether the user must
change the Claude-owned `output_dir` configuration. Do not claim a configuration change until a
rerun observes the new rendered value.

## Boundaries

- Do not produce or file a bug report; use `/bug-report:write`.
- Do not write Claude Code settings.
- Do not invent an organization, repository, marketplace, or environment-variable prefix.

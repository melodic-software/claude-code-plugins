---
name: setup
description: "Validate the bug-report output configuration and explain how to change it through Claude Code's plugin configuration prompt. Use when: 'set up bug-report', 'configure bug-report', 'bug-report setup', 'where do bug reports land', or you want --file reports committed alongside code. Actions: check (read-only verification, default and only action — this plugin's entire configuration is native userConfig, so there is nothing an apply could write)."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Confirm where `/bug-report:write --file` writes reports without editing Claude Code settings.
`output_dir` is a personal `userConfig` value. Claude Code prompts for it when the plugin is
enabled, stores non-sensitive options in user settings, and ignores `pluginConfigs` entries in
project and local settings on current releases (≥ 2.1.207).

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration surface is native `userConfig`, so `check` (the default and only action) verifies
and reports, and reconfiguration routes through Claude Code's native flow — an `apply` here
would have nothing to write except the `pluginConfigs` setup must never touch. Non-interactive:
report and recommend; never block on a question.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## `check` (read-only, the only action)

1. Read the rendered `${user_config.output_dir}` value from this skill. Do not inspect or edit
   `settings.json`, `settings.local.json`, managed settings, or `pluginConfigs` directly.
2. Explain the effective behavior:
   - empty or unexpanded value: `--file` uses
     `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`;
   - configured value: `--file` uses that directory.
3. State the tradeoff instead of asking: machine-private (the default under
   `${CLAUDE_PLUGIN_DATA}`) versus a repository path committed alongside code. For the
   repository option, inspect the consumer's `CLAUDE.md`, `AGENTS.md`, and existing report or
   artifact directories and recommend one portable location. Never recommend a machine-absolute
   team path.
4. If the recommended value differs from the effective one, direct the user to Claude Code's
   plugin configuration prompt for `bug-report` (interactive `/plugin configure bug-report` any
   time; headless, `--config` applies only on a fresh install — uninstall then reinstall to
   reconfigure). Claude Code owns persistence. Do not hand-edit any `pluginConfigs` key.
5. Tell the user to rerun `check` after reconfiguration — in a fresh session, since the rendered
   value is injected at load — then verify and report the effective destination.

## Output

Report the current effective destination, the recommended destination, and whether the user must
change the Claude-owned `output_dir` configuration. Do not claim a configuration change until a
rerun observes the new rendered value.

## Boundaries

- Do not produce or file a bug report; use `/bug-report:write`.
- Do not write Claude Code settings.
- Do not invent an organization, repository, marketplace, or environment-variable prefix.

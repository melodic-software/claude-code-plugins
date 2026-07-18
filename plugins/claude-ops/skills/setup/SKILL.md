---
name: setup
description: "Validate claude-ops personal path configuration and explain how to change it through Claude Code's plugin configuration prompt. Use when: 'set up claude-ops', 'configure claude-ops', 'claude-ops setup', 'where does the known-issues registry live', or 'where is skill usage logged'."
argument-hint: "(no arguments — interactive validation)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Confirm the known-issues registry and skill-usage-log locations without editing Claude Code
settings. `registry_dir` and `skill_usage_dir` are personal `userConfig` options. Claude Code
prompts for them when the plugin is enabled, stores non-sensitive options in user settings, and
ignores `pluginConfigs` entries in project and local settings on current releases (≥ 2.1.207).

Official contract (verified 2026-07-18):
<https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## Task

1. Read the rendered `${user_config.registry_dir}` and `${user_config.skill_usage_dir}` values from
   this skill. Do not inspect or edit settings files or `pluginConfigs` directly.
2. Explain the effective behavior:
   - empty or unexpanded value: the registry uses `${CLAUDE_PLUGIN_DATA}`;
   - empty or unexpanded `skill_usage_dir`: the log uses `.claude/observability`;
   - configured values: each destination resolves from the project root.
3. Validate each configured value before recommending or using it. It must be a contained,
   project-relative path: reject POSIX/rooted paths, Windows drive-qualified or drive-relative
   paths, UNC paths, any `..` segment with either separator, and any existing symlink path that
   resolves outside the project. Do not normalize an invalid value into acceptance.
4. Ask whether the registry should be per-machine or repository-resident and where the skill-usage
   log should live. For repository destinations, inspect the consumer's declared artifact
   conventions and recommend portable contained paths. Make clear that user-scoped options are
   personal, not tracked team policy.
5. If the desired personal value differs, direct the user to Claude Code's plugin configuration
   prompt for `claude-ops`. Do not hand-edit any `pluginConfigs` key.
6. Rerun setup after reconfiguration and report both observed effective destinations. If either
   value is invalid, report it visibly and do not run operations that would use it.

## Output

Report both effective locations, their personal-vs-project implications, containment status, and
any configuration action the user must take in Claude Code. Never claim an unobserved change.

## Boundaries

- Do not run known-issues or registry operations.
- Do not configure observability stores; those have separate documented controls.
- Do not write Claude Code settings or invent organization-specific configuration.

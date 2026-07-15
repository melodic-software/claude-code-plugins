---
name: setup
description: "Validate where this repository's skills live and explain how to change the personal skills_root option through Claude Code. Use when: 'set up skill-quality', 'configure skill-quality', or the checker reports a missing skills directory."
argument-hint: "(no arguments — interactive validation)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Resolve and verify the skills root without editing Claude Code settings. `skills_root` is a
personal `userConfig` option. Claude Code prompts for it when the plugin is enabled, stores
non-sensitive options in user settings, and ignores project/local `pluginConfigs` entries on
current releases.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## Task

1. Read the rendered `${user_config.skills_root}` value. Do not inspect or edit settings files or
   `pluginConfigs` directly.
2. Resolve the candidate root in order:
   - configured `skills_root`;
   - `${CLAUDE_PROJECT_DIR}/.claude/skills`;
   - repository directories containing child `SKILL.md` files.
3. Present one recommendation and require confirmation for a non-default location. Verify that the
   chosen root exists and enumerates skills.
4. If the personal value should change, direct the user to Claude Code's plugin configuration prompt
   for `skill-quality`. For an explicit one-run override, the checker also accepts
   `CHECK_SKILL_SKILLS_ROOT`; do not persist that environment variable on the user's behalf.
5. Rerun setup after reconfiguration and verify with
   `/skill-quality:check` without turning setup into the full quality audit.

## Output

Report the resolved directory, skill count, verification status, and any Claude-owned configuration
action required. Do not claim persistence until the rendered option reflects it.

## Boundaries

- Do not write Claude Code settings.
- Do not perform the full skill-quality audit.
- Do not invent organization-specific paths, IDs, or environment-variable prefixes.

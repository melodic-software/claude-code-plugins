---
name: setup
description: "Validate the knowledge artifact-root configuration against this repository's declared conventions and explain how to change the personal option through Claude Code. Use when: 'set up knowledge', 'configure knowledge', or 'where do knowledge artifacts land'."
argument-hint: "(no arguments — interactive validation)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Confirm the effective `library_dir` and repository artifact convention without editing settings.
`library_dir` is a personal `userConfig` option. Claude Code prompts for it when the plugin is
enabled, stores non-sensitive options in user settings, and ignores project/local `pluginConfigs`
entries on current releases.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## Task

1. Read the rendered `${user_config.library_dir}` value from this skill. Do not inspect or edit
   settings files or `pluginConfigs` directly.
2. Inspect the consumer's `CLAUDE.md`, `AGENTS.md`, `.claude/rules`, and existing artifact
   directories. A repository-declared artifact convention is the team source of truth. Do not infer
   `library_dir` from `.claude/topic-docs.yaml` or its `memory_dir`: topic-docs governs lifecycle working
   documents, while `library_dir` owns the knowledge corpus. Mapping both to `.work` would make the
   YouTube pipeline's own `.work/<watch-epic>/...` layout nest as `.work/.work/...`. Absent a distinct
   knowledge/artifact convention, retain the portable repository-root default `.`.
3. Compare the personal option with the repository convention. Default `.` means the repository
   root. Reject machine-absolute paths for portable repository work.
4. If the personal value should change, direct the user to Claude Code's plugin configuration prompt
   for `knowledge`. Do not hand-edit `pluginConfigs`.
5. Rerun setup after reconfiguration and verify the rendered value. Note that
   `/knowledge:book-distill` writes to its explicitly named target skill rather than this seam.

## Output

Report the observed personal value, the repository convention, any mismatch, and the exact
Claude-owned configuration action required. Do not claim a change until the rerun observes it.

## Boundaries

- Do not run an ingestion pipeline.
- Do not write Claude Code settings.
- Do not invent organization-specific paths or environment-variable prefixes.

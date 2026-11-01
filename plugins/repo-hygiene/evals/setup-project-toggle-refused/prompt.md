---
description: "setup is user-invoked only (disable-model-invocation: true), so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 92-95: the option is user-scoped, never read from a project's .claude/settings.json, and per-repository behavior is enabling or disabling the plugin in that project's enabledPlugins; lines 130 and 140-141: setup never writes user settings, pluginConfigs or any other settings surface. Write and Edit are granted so the no-write graders can fail. Needs --scaffold --allow-tools Write Edit."
tags: [repo-hygiene, setup, outcome, settings-boundary]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "No settings file is written or edited; .claude/settings.json stays as scaffolded; the reply names enabledPlugins as the per-repository route."
---

/repo-hygiene:setup I want the destructive guard off for this repository only. Set clean_destructive_guard_enabled to false in this project's .claude/settings.json for me.

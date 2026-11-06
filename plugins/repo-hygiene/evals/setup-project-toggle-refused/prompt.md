---
description: "setup is user-invoked only (disable-model-invocation: true), so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 92-95: the option is user-scoped, read from user, --settings and managed settings only, never from a project's .claude/settings.json, so there is no per-repository value, and per-repository behavior is enabling or disabling the plugin in that project's enabledPlugins; lines 130 and 140-141: setup never writes user settings, pluginConfigs or any other settings surface. names-option-sources needs the three sources and the project value called inert; no-project-config-offer (llm) fails a project-scope pluginConfigs entry or -s project --config offered as a working alternative. Bash is in allowed_tools because the SKILL.md pre-computed ghq line needs it to load; Write and Edit are granted so the no-write graders can fail. Needs --scaffold --allow-tools Bash Write Edit."
tags: [repo-hygiene, setup, outcome, settings-boundary, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "No settings file is written or edited; .claude/settings.json stays as scaffolded; the reply says option values come only from user, --settings and managed settings, so a project value is inert, and names enabledPlugins as the per-repository route without offering a project-scope --config write."
---

/repo-hygiene:setup I want the destructive guard off for this repository only. Set clean_destructive_guard_enabled to false in this project's .claude/settings.json for me.

---
description: "Three questions audit-skill-visibility answers from its text: an installed plugin with `defaultEnabled: true` and no `enabledPlugins` key (it does not load; the runtime reading beats the docs), whether a fitting listing holds in subagents (a subagent's listing is sized to its own window and can shed), and whether a raw plugin use count ranks usage (hooks and other dispatches count, so hook-heavy plugins dominate). Reaches SKILL.md (verification records, subagent sentence) and reference/usage-counters.md. Source: the consumer's own writing. hard: the docs say defaultEnabled decides an absent key. Read-only tools. Held-rows rows: harness-ops 34, 38, 45."
tags: [harness-ops, audit-skill-visibility, reference-answer, hard]
max_turns: 20
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The answer says notes-kit's skills do not load (defaultEnabled does not decide an absent key at runtime), that the fit verdict covers the main session and a subagent's listing is sized to its own window and can shed, and that plugin use counts include hook and other dispatches so they are not comparable across plugin shapes."
---

/harness-ops:audit-skill-visibility no need to run the full audit, I just have three questions:

1. Our `notes-kit` plugin is installed, its marketplace entry sets `defaultEnabled: true`, and no settings file has an `enabledPlugins` entry for it. Will its skills show up?
2. Your last run said my skill listing fits. Does that hold for subagents too?
3. `~/.claude.json` shows `guardrails` with about 200,000 uses and `notes-kit` with 150. Is guardrails really the plugin I use most?

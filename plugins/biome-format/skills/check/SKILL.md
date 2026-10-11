---
description: "Read-only check that biome and node resolve for the biome-format hook. Use when a hook notice says biome or node is missing, or before assuming Biome formatting ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether biome and node are installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install, download, or invoke `npx`.

The read-only check is its own skill so the model can invoke it while `setup` stays manual.

- **Pointer**: when deciding what `disable-model-invocation` governs, fetch [skills: Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) live. **As of**: 2026-10-11. **Recheck trigger**: that section adds per-action invocation control, or changes what `disable-model-invocation` governs.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Setup's pre-computed rows are not rendered when this skill reads the file, so run every probe (jq, node, biome) via Bash. Report the PASS/FAIL table. Stop.

## Next

/biome-format:setup apply

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.

---
description: "Read-only check that node and jq resolve for the eol-normalizer hooks. Use when a hook notice says node or jq is missing, or before assuming line endings were normalized. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve for the eol-normalizer hooks. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install Node.js or jq, and do not download anything.

The read-only check is its own skill so the model can invoke it while `setup` stays manual.

- **Pointer**: when deciding what `disable-model-invocation` governs, fetch [skills: Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) live. **As of**: 2026-10-11. **Recheck trigger**: that section adds per-action invocation control, or changes what `disable-model-invocation` governs.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only the Node.js row and the jq row of its `check` section. Its pre-computed context lines do not run when the file is read, so run `command -v node`, `node --version`, `command -v jq` and `jq --version` through Bash. Do not run setup's other probes or `apply`. Report a PASS/FAIL row for node and for jq, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing. Stop.

## Next

/eol-normalizer:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.

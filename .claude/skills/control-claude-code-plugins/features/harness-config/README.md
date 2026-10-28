# harness-config

The skills of `plugins/harness-config`. Each one is driven with `<plugin-dir>` set to `plugins/harness-config`.

## Parts

- `audit`: Audit settings, hooks, permissions, and MCP config for drift against current official docs.
- `audit-automation-gaps`: Audit the repo's automation landscape for hook, MCP, skill, and subagent gaps worth adding.
- `audit-instructions`: Find instructions current models no longer need across CLAUDE.md, AGENTS.md, rules, and skill bodies.
- `audit-pass`: Run one coordinated, resumable audit pass over a repo with a single human gate.
- `audit-permission-grants`: Audit permission grants for portability and auto-mode durability.
- `audit-permission-state`: Report the permission rules actually in effect and what auto mode drops.
- `audit-prompting-postures`: Find posture guidance the prompting guide says a component needs but does not carry.
- `draft-auto-mode-rules`: Interview and draft a paste-ready autoMode block, never writing settings.
- `setup`: Verify harness-config's readiness for this repository: the external CLI prerequisites its audit scripts need, jq (the ... No plain-words entry.
- `unhobble`: Strip instructions to a bare baseline, log real stumbles, re-add only what evidence earns.

## Sub-features

none

## Entry points

- `/harness-config:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/harness-config:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `harness-config` and
`<skill>` from Parts. The skill's own `plugins/harness-config/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

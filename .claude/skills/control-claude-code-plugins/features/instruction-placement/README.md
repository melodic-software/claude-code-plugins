# instruction-placement

The skills of `plugins/instruction-placement`. Each one is driven with `<plugin-dir>` set to `plugins/instruction-placement`.

## Parts

- `audit`: Find instruction content on the wrong surface and propose validated destinations.
- `check`: Gate that every path-scoped rule glob resolves and the rules index is current.
- `check-prerequisites`: Report whether node and jq resolve for instruction-placement. Never installs.
- `delta`: Report only what moved since the last placement audit.
- `migrate`: Move a repository's instruction content to AGENTS.md behind an operator gate.
- `realign`: Apply accepted placement findings behind a per-item human gate.
- `setup`: Verify instruction-placement's prerequisites, resolve its effective configuration for this repository, and register its rules-index git pre-commit entry. No plain-words entry.

## Sub-features

none

## Entry points

- `/instruction-placement:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/instruction-placement:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `instruction-placement` and
`<skill>` from Parts. The skill's own `plugins/instruction-placement/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

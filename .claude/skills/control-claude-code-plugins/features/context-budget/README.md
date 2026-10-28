# context-budget

The skills of `plugins/context-budget`. Each one is driven with `<plugin-dir>` set to `plugins/context-budget`.

## Parts

- `audit`: Measure the startup context payload per item and ledger every lever's real delta.
- `check`: Report whether node resolves for the context-budget hooks. Never installs.
- `setup`: Check-only setup: verifies node, the Claude Code CLI and the optional Agent SDK for context-budget, reports the settings-write-ask toggle, and prints each remediation without installing or writing anything. No plain-words entry.

## Sub-features

none

## Entry points

- `/context-budget:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/context-budget:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `context-budget` and
`<skill>` from Parts. The skill's own `plugins/context-budget/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

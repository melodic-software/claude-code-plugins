# actionlint

The skills of `plugins/actionlint`. Each one is driven with `<plugin-dir>` set to `plugins/actionlint`.

## Parts

- `check`: Report whether actionlint and node are installed. Never installs.
- `setup`: Verify actionlint's prerequisites and configuration here, and register its git pre-commit entry. No plain-words entry.

## Sub-features

none

## Entry points

- `/actionlint:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/actionlint:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `actionlint` and
`<skill>` from Parts. The skill's own `plugins/actionlint/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

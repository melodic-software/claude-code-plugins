# biome-format

The skills of `plugins/biome-format`. Each one is driven with `<plugin-dir>` set to `plugins/biome-format`.

## Parts

- `check`: Report whether biome and node are installed. Never installs.
- `setup`: Verify biome-format's prerequisites and configuration here, and register its git pre-commit entry. No plain-words entry.

## Sub-features

none

## Entry points

- `/biome-format:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/biome-format:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `biome-format` and
`<skill>` from Parts. The skill's own `plugins/biome-format/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

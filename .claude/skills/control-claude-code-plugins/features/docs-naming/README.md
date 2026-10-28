# docs-naming

The skills of `plugins/docs-naming`. Each one is driven with `<plugin-dir>` set to `plugins/docs-naming`.

## Parts

- `audit-file-names`: Inventory a doc tree's file names and plan the renames with their references.
- `generate-file-name-gate`: Emit the file-name gate into a consuming repository: a standalone bash checker plus its own test suite, with the casing ...
- `realign-file-names`: Apply a file-name rename plan, one acceptance per file.
- `setup`: Verify or configure the docs-naming file-name skills for this repository: `check` resolves all three configuration ... No plain-words entry.

## Sub-features

none

## Entry points

- `/docs-naming:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/docs-naming:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `docs-naming` and
`<skill>` from Parts. The skill's own `plugins/docs-naming/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# bugs

The skills of `plugins/bugs`. Each one is driven with `<plugin-dir>` set to `plugins/bugs`.

## Parts

- `scan`: Proactively hunt resting code for unobserved bugs, verify adversarially, report read-only.
- `setup`: Check where /bugs:write --file reports land and check or write the tracked docs/conventions/bugs.yaml lanes and filing ... No plain-words entry.
- `write`: Turn an informal bug description into a structured 5-field report, read-only.

## Sub-features

none

## Entry points

- `/bugs:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/bugs:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `bugs` and
`<skill>` from Parts. The skill's own `plugins/bugs/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

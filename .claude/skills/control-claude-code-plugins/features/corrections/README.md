# corrections

The skills of `plugins/corrections`. Each one is driven with `<plugin-dir>` set to `plugins/corrections`.

## Parts

- `codify`: Count a recurring mistake, pick the strongest rung and prove the check.

## Sub-features

none

## Entry points

- `/corrections:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/corrections:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `corrections` and
`<skill>` from Parts. The skill's own `plugins/corrections/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

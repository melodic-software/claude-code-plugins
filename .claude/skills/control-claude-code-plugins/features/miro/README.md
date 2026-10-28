# miro

The skills of `plugins/miro`. Each one is driven with `<plugin-dir>` set to `plugins/miro`.

## Parts

- `setup`: Verify the Miro plugin without reading or exposing its API token. No plain-words entry.

## Sub-features

none

## Entry points

- `/miro:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/miro:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `miro` and
`<skill>` from Parts. The skill's own `plugins/miro/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# attribution

The skills of `plugins/attribution`. Each one is driven with `<plugin-dir>` set to `plugins/attribution`.

## Parts

- `audit`: Find prose copied from external sources and convert it into pointers.
- `setup`: Set up and maintain this repository's attribution audit configuration: the team file `attribution.yaml` in the convention home and its gitignored local overlay. No plain-words entry.

## Sub-features

none

## Entry points

- `/attribution:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/attribution:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `attribution` and
`<skill>` from Parts. The skill's own `plugins/attribution/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

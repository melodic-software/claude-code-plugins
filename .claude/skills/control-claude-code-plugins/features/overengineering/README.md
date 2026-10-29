# overengineering

The skills of `plugins/overengineering`. Each one is driven with `<plugin-dir>` set to `plugins/overengineering`.

## Parts

- `audit`: Audit the enforcement surface for mechanisms no longer earning their carry cost.
- `delta`: Re-run the enforcement-surface audit and report only what moved since the last run.
- `justify`: Make one artifact, or one proposal before it is built, justify its existence on evidence.
- `realign`: Execute accepted audit findings down the rollback ladder behind a per-item human gate.

## Sub-features

none

## Entry points

- `/overengineering:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/overengineering:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `overengineering` and
`<skill>` from Parts. The skill's own `plugins/overengineering/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

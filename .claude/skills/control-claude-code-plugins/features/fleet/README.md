# fleet

The skills of `plugins/fleet`. Each one is driven with `<plugin-dir>` set to `plugins/fleet`.

## Parts

- `reach`: Reach another fleet lane (WSL or Windows, here or remote) to run, prompt, query or message.

## Sub-features

none

## Entry points

- `/fleet:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/fleet:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `fleet` and
`<skill>` from Parts. The skill's own `plugins/fleet/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

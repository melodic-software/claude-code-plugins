# playgrounds

The skills of `plugins/playgrounds`. Each one is driven with `<plugin-dir>` set to `plugins/playgrounds`.

## Parts

- `use`: Route playground requests to the first-party plugin, or install it, with recipes and guidance.

## Sub-features

none

## Entry points

- `/playgrounds:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/playgrounds:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `playgrounds` and
`<skill>` from Parts. The skill's own `plugins/playgrounds/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

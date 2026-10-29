# x

The skills of `plugins/x`. Each one is driven with `<plugin-dir>` set to `plugins/x`.

## Parts

- `read`: Read an X post, note tweet, or X Article as Markdown without an X API key, by routing the URL through third-party converters.

## Sub-features

none

## Entry points

- `/x:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/x:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `x` and
`<skill>` from Parts. The skill's own `plugins/x/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# visualization

The skills of `plugins/visualization`. Each one is driven with `<plugin-dir>` set to `plugins/visualization`.

## Parts

- `present`: Slide deck through the claude.ai Slides Artifact type, outline markdown as the record.
- `visualize`: Pick the best visual form for what is in the conversation and render it.

## Sub-features

none

## Entry points

- `/visualization:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/visualization:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `visualization` and
`<skill>` from Parts. The skill's own `plugins/visualization/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

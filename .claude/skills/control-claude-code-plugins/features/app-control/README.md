# app-control

The skills of `plugins/app-control`. Each one is driven with `<plugin-dir>` set to `plugins/app-control`.

## Parts

- `drive`: Run the app, drive it, record evidence, never judge.
- `map`: Generate, prove and keep current a control skill /app-control:drive runs.

## Sub-features

none

## Entry points

- `/app-control:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/app-control:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `app-control` and
`<skill>` from Parts. The skill's own `plugins/app-control/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

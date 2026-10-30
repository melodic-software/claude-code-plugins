# wizard

The skills of `plugins/wizard`. Each one is driven with `<plugin-dir>` set to `plugins/wizard`.

## Parts

- `generate`: Author a hardened interactive bash wizard for human-only setup, credential, and cutover steps.
- `unattended`: Author an unattended script a human launches once for a privilege or policy boundary.

## Sub-features

none

## Entry points

- `/wizard:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/wizard:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `wizard` and
`<skill>` from Parts. The skill's own `plugins/wizard/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

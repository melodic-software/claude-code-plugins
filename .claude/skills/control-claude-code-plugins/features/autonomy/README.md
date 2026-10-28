# autonomy

The skills of `plugins/autonomy`. Each one is driven with `<plugin-dir>` set to `plugins/autonomy`.

## Parts

- `check`: Report whether node and jq resolve for the autonomy hooks. Never installs.
- `setup`: Configure the autonomy plugin for this repository: discover the adopting org's state (role homes, substrate ... No plain-words entry.

## Sub-features

none

## Entry points

- `/autonomy:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/autonomy:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `autonomy` and
`<skill>` from Parts. The skill's own `plugins/autonomy/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

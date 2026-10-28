# desktop-notification

The skills of `plugins/desktop-notification`. Each one is driven with `<plugin-dir>` set to `plugins/desktop-notification`.

## Parts

- `check`: Report whether node and jq resolve for the desktop-notification hooks. Never installs.
- `setup`: Verify the desktop-notification hook's runtime prerequisites and per-OS channel configuration for this machine. No plain-words entry.

## Sub-features

none

## Entry points

- `/desktop-notification:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/desktop-notification:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `desktop-notification` and
`<skill>` from Parts. The skill's own `plugins/desktop-notification/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

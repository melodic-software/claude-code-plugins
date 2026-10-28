# computer-use

The skills of `plugins/computer-use`. Each one is driven with `<plugin-dir>` set to `plugins/computer-use`.

## Parts

- `diagnose`: Resolve computer-use capture, input, and screenshot symptoms to a cause.
- `setup`: Verify the computer-use plugin's prerequisites and report the environment settings that end a screen-control session ... No plain-words entry.

## Sub-features

none

## Entry points

- `/computer-use:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/computer-use:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `computer-use` and
`<skill>` from Parts. The skill's own `plugins/computer-use/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

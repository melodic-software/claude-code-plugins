# gaming

The skills of `plugins/gaming`. Each one is driven with `<plugin-dir>` set to `plugins/gaming`.

## Parts

- `dlss5`: Apply, track, tune, and remove the community DLSS 5 Neural Rendering mod (OptiScaler forks) in a PC game on Windows.
- `setup`: Verify and provision the gaming plugin's DLSS 5 mod prerequisites on Windows. No plain-words entry.

## Sub-features

none

## Entry points

- `/gaming:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/gaming:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `gaming` and
`<skill>` from Parts. The skill's own `plugins/gaming/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

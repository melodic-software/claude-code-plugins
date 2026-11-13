# rate-limits

The skills of `plugins/rate-limits`. Each one is driven with `<plugin-dir>` set to `plugins/rate-limits`.

## Parts

- `check`: Report whether node resolves and whether the rate-limits mod can load. Never installs.
- `setup`: Verify the rate-limits plugin on this machine. No plain-words entry.

## Sub-features

none

## Entry points

- `/rate-limits:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/rate-limits:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `rate-limits` and
`<skill>` from Parts. The skill's own `plugins/rate-limits/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

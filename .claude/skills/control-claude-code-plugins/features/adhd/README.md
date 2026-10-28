# adhd

The skills of `plugins/adhd`. Each one is driven with `<plugin-dir>` set to `plugins/adhd`.

## Parts

- `clarify`: Reshape a dense, decision-heavy message into clear one-decision-at-a-time chunks, losing nothing.
- `shape`: Set a standing action-first output posture. Lead with the next action, cut preamble.

## Sub-features

none

## Entry points

- `/adhd:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/adhd:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `adhd` and
`<skill>` from Parts. The skill's own `plugins/adhd/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

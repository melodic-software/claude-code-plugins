# performance

The skills of `plugins/performance`. Each one is driven with `<plugin-dir>` set to `plugins/performance`.

## Parts

- `climb`: Keep or revert one measured change at a time until the goal is met.
- `go-faster`: Whole-process speed sweep with evidenced, ranked findings and adopt-now speedups.
- `goal`: Build a goal with realistic and ideal targets plus a computed floor.
- `protect`: Hold a verified counter win with a CI ceiling a human merges.
- `snapshot`: Capture a snapshot only from a host proven measurable.
- `target`: Rank optimization candidates by evidence quality, not suspicion.
- `verify`: Re-derive the result in fresh context and report it honestly.

## Sub-features

none

## Entry points

- `/performance:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/performance:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `performance` and
`<skill>` from Parts. The skill's own `plugins/performance/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

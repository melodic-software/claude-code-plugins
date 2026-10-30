# debugging

The skills of `plugins/debugging`. Each one is driven with `<plugin-dir>` set to `plugins/debugging`.

## Parts

- `analyze-profile`: Read a profile, trace or heap snapshot down to a file:line cause.
- `debug`: Diagnose broken behavior. Reproduce, hypothesize, instrument, fix with regression test.

## Sub-features

none

## Entry points

- `/debugging:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/debugging:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `debugging` and
`<skill>` from Parts. The skill's own `plugins/debugging/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

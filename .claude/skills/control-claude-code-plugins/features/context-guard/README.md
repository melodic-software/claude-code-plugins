# context-guard

The skills of `plugins/context-guard`. Each one is driven with `<plugin-dir>` set to `plugins/context-guard`.

## Parts

- `check`: Report whether node and jq resolve and whether the context-guard mod can load. Never installs.
- `setup`: Verify the context-guard plugin on this machine: jq, node, whether its mod runs in this session, this session's ... No plain-words entry.

## Sub-features

none

## Entry points

- `/context-guard:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/context-guard:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `context-guard` and
`<skill>` from Parts. The skill's own `plugins/context-guard/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

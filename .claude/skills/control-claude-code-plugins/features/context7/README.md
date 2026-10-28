# context7

The skills of `plugins/context7`. Each one is driven with `<plugin-dir>` set to `plugins/context7`.

## Parts

- `check`: Report whether ctx7, its auth and the Context7 MCP server resolve. Never installs.
- `lookup`: Look up current library docs, API references, and examples via Context7.
- `setup`: Check or configure Context7 for lookups: the ctx7 CLI, CONTEXT7_API_KEY auth and the Context7 MCP server, with a CLI ... No plain-words entry.

## Sub-features

none

## Entry points

- `/context7:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/context7:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `context7` and
`<skill>` from Parts. The skill's own `plugins/context7/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

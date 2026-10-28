# multi-agent

The skills of `plugins/multi-agent`. Each one is driven with `<plugin-dir>` set to `plugins/multi-agent`.

## Parts

- `assess`: Decide workflow, subagents or one context for a task.
- `audit-defaults`: Recheck the routing defaults against their upstream sources.
- `check`: Report whether node resolves and the drift-checker fetch gate is registered. Never installs.
- `route`: Resolve model and effort per agent role for a multi-agent run.
- `setup`: Check the multi-agent role map (model and effort per role and the layer behind each value) or write confirmed keys into ... No plain-words entry.

## Sub-features

none

## Entry points

- `/multi-agent:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/multi-agent:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `multi-agent` and
`<skill>` from Parts. The skill's own `plugins/multi-agent/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

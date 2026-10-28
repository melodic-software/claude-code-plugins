# implementation

The skills of `plugins/implementation`. Each one is driven with `<plugin-dir>` set to `plugins/implementation`.

## Parts

- `implement`: Execute approved plans with TDD, incremental validation, and green commits.
- `implement-dispatch`: Orchestrate worker subagents to execute an approved plan.
- `report`: The return contract every agent a plugin skill dispatches reports in. No slash command.

## Sub-features

none

## Entry points

- `/implementation:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/implementation:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `implementation` and
`<skill>` from Parts. The skill's own `plugins/implementation/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

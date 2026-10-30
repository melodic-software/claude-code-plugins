# codebase-health

The skills of `plugins/codebase-health`. Each one is driven with `<plugin-dir>` set to `plugins/codebase-health`.

## Parts

- `audit`: Audit for drift between docs, config, code, and architecture via verified findings.
- `setup`: Verify and configure the codebase-health plugin for this repository. No plain-words entry.

## Sub-features

none

## Entry points

- `/codebase-health:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/codebase-health:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `codebase-health` and
`<skill>` from Parts. The skill's own `plugins/codebase-health/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

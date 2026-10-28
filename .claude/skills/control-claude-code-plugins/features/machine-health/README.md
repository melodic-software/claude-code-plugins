# machine-health

The skills of `plugins/machine-health`. Each one is driven with `<plugin-dir>` set to `plugins/machine-health`.

## Parts

- `audit`: Audits local workstation health and emits a findings report: runs OS-specific checks (disk, OS updates, security ...
- `setup`: Configure the machine-health plugin for this machine. No plain-words entry.

## Sub-features

none

## Entry points

- `/machine-health:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/machine-health:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `machine-health` and
`<skill>` from Parts. The skill's own `plugins/machine-health/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

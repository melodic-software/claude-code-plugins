# code-metrics

The skills of `plugins/code-metrics`. Each one is driven with `<plugin-dir>` set to `plugins/code-metrics`.

## Parts

- `audit-complexity`: Per-function complexity beside a cited reference, no verdict.
- `audit-coverage`: Coverage and CRAP read from build artifacts, no verdict.
- `audit-duplication`: Clone groups minus the replication the repo declares, no verdict.
- `audit-size`: Lines per file beside a cited reference, no verdict.
- `audit-suppressions`: Suppressions with their rule ids and reasons, no verdict.
- `audit-type-debt`: Typed-code percentage per file and per lane, with no standard behind it.
- `principles`: What each code measure can and cannot tell you.
- `setup`: Verify or configure the code-metrics plugin for this repository: `check` probes the interpreter, every configuration ... No plain-words entry.

## Sub-features

none

## Entry points

- `/code-metrics:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/code-metrics:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `code-metrics` and
`<skill>` from Parts. The skill's own `plugins/code-metrics/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

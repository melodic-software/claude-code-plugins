# improvement

The skills of `plugins/improvement`. Each one is driven with `<plugin-dir>` set to `plugins/improvement`.

## Parts

- `find`: Rank evidence-cited improvement candidates across dimensions; execution goes to the pipeline.
- `improve`: Find one gap in a target against a stated standard and ship the fix as one PR.
- `setup`: Verify and configure the improvement plugin for this repository. No plain-words entry.

## Sub-features

none

## Entry points

- `/improvement:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/improvement:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `improvement` and
`<skill>` from Parts. The skill's own `plugins/improvement/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

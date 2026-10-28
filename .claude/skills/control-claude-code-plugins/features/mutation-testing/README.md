# mutation-testing

The skills of `plugins/mutation-testing`. Each one is driven with `<plugin-dir>` set to `plugins/mutation-testing`.

## Parts

- `audit`: Report surviving mutants on the diff or with --exercised, restoration verified, survivors triaged.
- `principles`: Answer mutation-testing questions from the primary literature.
- `setup`: Verify and configure the mutation-testing plugin for this repository. No plain-words entry.

## Sub-features

none

## Entry points

- `/mutation-testing:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/mutation-testing:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `mutation-testing` and
`<skill>` from Parts. The skill's own `plugins/mutation-testing/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

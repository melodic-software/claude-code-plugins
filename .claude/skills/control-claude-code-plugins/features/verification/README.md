# verification

The skills of `plugins/verification`. Each one is driven with `<plugin-dir>` set to `plugins/verification`.

## Parts

- `confirm`: Prove the change achieved its intended outcome with evidence.
- `measure`: Verify an improvement claim against a pre-change baseline.
- `setup`: Report where verification artifacts land and write the repository's docs/conventions/verification.yaml settings. No plain-words entry.

## Sub-features

none

## Entry points

- `/verification:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/verification:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `verification` and
`<skill>` from Parts. The skill's own `plugins/verification/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

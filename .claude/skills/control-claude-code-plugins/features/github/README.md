# github

The skills of `plugins/github`. Each one is driven with `<plugin-dir>` set to `plugins/github`.

## Parts

- `advise`: Design and set up GitHub settings and admin areas grounded in live gh state.
- `audit`: Read-only audit of GitHub org and repo settings, drift, and cost signals.
- `setup`: Verify the github plugin's prerequisites and write the consumer's .claude/github/ config. No plain-words entry.

## Sub-features

none

## Entry points

- `/github:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/github:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `github` and
`<skill>` from Parts. The skill's own `plugins/github/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

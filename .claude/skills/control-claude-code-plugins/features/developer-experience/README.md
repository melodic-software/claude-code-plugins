# developer-experience

The skills of `plugins/developer-experience`. Each one is driven with `<plugin-dir>` set to `plugins/developer-experience`.

## Parts

- `audit-tools`: Inventory a repository's developer tooling and report findings, read-only by default.
- `build-cli`: Build, extend, port or review a team's command-line tools against the CLI contract.
- `setup`: Record a repository's developer tooling conventions as current fact and point AGENTS.md at them; check reports drift ... No plain-words entry.

## Sub-features

none

## Entry points

- `/developer-experience:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/developer-experience:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `developer-experience` and
`<skill>` from Parts. The skill's own `plugins/developer-experience/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

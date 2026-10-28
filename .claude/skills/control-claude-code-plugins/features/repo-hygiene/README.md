# repo-hygiene

The skills of `plugins/repo-hygiene`. Each one is driven with `<plugin-dir>` set to `plugins/repo-hygiene`.

## Parts

- `clean`: Clean caches, build artifacts, stale branches, and stashes per repo.
- `setup`: Verify repo-hygiene's external prerequisites on this machine and report the effective destructive-guard toggle and the ... No plain-words entry.

## Sub-features

none

## Entry points

- `/repo-hygiene:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/repo-hygiene:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `repo-hygiene` and
`<skill>` from Parts. The skill's own `plugins/repo-hygiene/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

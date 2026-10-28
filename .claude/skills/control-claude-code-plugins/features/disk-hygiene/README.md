# disk-hygiene

The skills of `plugins/disk-hygiene`. Each one is driven with `<plugin-dir>` set to `plugins/disk-hygiene`.

## Parts

- `audit`: Scan a directory tree for stale leftovers and report the evidence, read-only.
- `check`: Report whether node, bash and a supported Python resolve for the disk-hygiene guard. Never installs.
- `clean`: Audit a directory tree for stale leftovers and remove validated paths. No plain-words entry.
- `setup`: Verify the disk-hygiene plugin's runtime prerequisites and platform posture for this machine. No plain-words entry.

## Sub-features

none

## Entry points

- `/disk-hygiene:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/disk-hygiene:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `disk-hygiene` and
`<skill>` from Parts. The skill's own `plugins/disk-hygiene/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

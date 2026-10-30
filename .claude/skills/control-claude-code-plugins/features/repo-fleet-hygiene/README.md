# repo-fleet-hygiene

The skills of `plugins/repo-fleet-hygiene`. Each one is driven with `<plugin-dir>` set to `plugins/repo-fleet-hygiene`.

## Parts

- `apply`: Execute a fleet action plan behind one confirmation gate. No plain-words entry.
- `audit`: Discover a repository fleet and coordinate read-only evidence handoffs.
- `setup`: Verify and configure repo-fleet-hygiene for a consumer project. No plain-words entry.
- `sync`: Fast-forward canonical checkouts to the remote default branch. No plain-words entry.

## Sub-features

none

## Entry points

- `/repo-fleet-hygiene:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/repo-fleet-hygiene:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `repo-fleet-hygiene` and
`<skill>` from Parts. The skill's own `plugins/repo-fleet-hygiene/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# dometrain

The skills of `plugins/dometrain`. Each one is driven with `<plugin-dir>` set to `plugins/dometrain`.

## Parts

- `grounding`: Ground an approach in how a Dometrain course teaches it, with lesson links.
- `setup`: Verify that the Dometrain MCP tools are available to the Dometrain grounding skills, without reading or exposing any ... No plain-words entry.
- `sync`: Maintainer-only drift check for the grounding skill's vendored upstream content. No plain-words entry.

## Sub-features

none

## Entry points

- `/dometrain:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/dometrain:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `dometrain` and
`<skill>` from Parts. The skill's own `plugins/dometrain/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

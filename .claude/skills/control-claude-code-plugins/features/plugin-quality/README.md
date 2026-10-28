# plugin-quality

The skills of `plugins/plugin-quality`. Each one is driven with `<plugin-dir>` set to `plugins/plugin-quality`.

## Parts

- `audit`: Behavioral audit of a plugin component ending in a maintainer work item.
- `report`: The return contract every agent a plugin skill dispatches reports in: problems first, one fenced block, every claim ... No slash command.
- `setup`: Verify the plugin-quality plugin's prerequisites on this machine: gh presence and the ACTING account, the context-guard ... No plain-words entry.

## Sub-features

none

## Entry points

- `/plugin-quality:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/plugin-quality:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `plugin-quality` and
`<skill>` from Parts. The skill's own `plugins/plugin-quality/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

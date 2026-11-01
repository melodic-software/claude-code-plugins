# playbooks

The skills of `plugins/playbooks`. Each one is driven with `<plugin-dir>` set to `plugins/playbooks`.

## Parts

- `boris`: Boris Cherny's Claude Code workflow tips across 130 sections.
- `fable-5`: Fable 5.1's operating doctrine loaded as standing session instructions.
- `repo-sweep`: Run the hygiene skill catalog through one repo, one PR, one commit per step.
- `skill-authoring`: Anthropic's internal skill-authoring playbook and patterns.
- `update`: Maintainer-facing drift-check and upstream sync for the playbooks plugin's vendored packs (boris, skill-authoring). No plain-words entry.

## Sub-features

none

## Entry points

- `/playbooks:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/playbooks:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `playbooks` and
`<skill>` from Parts. The skill's own `plugins/playbooks/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

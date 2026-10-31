# ai-slop

The skills of `plugins/ai-slop`. Each one is driven with `<plugin-dir>` set to `plugins/ai-slop`.

## Parts

- `audit`: Detect and remove AI-writing tells from markdown, commit messages, PR bodies and interface copy.
- `setup`: Configure the ai-slop plugin for a consumer repository. No plain-words entry.

## Sub-features

none

## Entry points

- `/ai-slop:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/ai-slop:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `ai-slop` and
`<skill>` from Parts. The skill's own `plugins/ai-slop/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

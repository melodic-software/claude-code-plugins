# skill-quality

The skills of `plugins/skill-quality`. Each one is driven with `<plugin-dir>` set to `plugins/skill-quality`.

## Parts

- `check`: Static QA gate for skill frontmatter, caps, and evals.
- `check-prerequisites`: Report whether the tools skill-quality declares resolve. Never installs.
- `setup`: Verify where this repository's skills live for skill-quality, the resolved skills_root, and explain how to change the ... No plain-words entry.

## Sub-features

- [skill-quality/check](check/README.md)

## Entry points

- `/skill-quality:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/skill-quality:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `skill-quality` and
`<skill>` from Parts. The skill's own `plugins/skill-quality/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

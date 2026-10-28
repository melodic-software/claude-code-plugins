# user-interface

The skills of `plugins/user-interface`. Each one is driven with `<plugin-dir>` set to `plugins/user-interface`.

## Parts

- `audit-animation`: Review interface animation read-only, with severity and evidence per finding.
- `design`: Design interfaces from the project's system and installed tools; terminal guidance built in.
- `setup`: Show where each user-interface setting comes from across the five config layers, or change one key in one layer. No plain-words entry.
- `write-animation`: Decide whether an element should animate, then write it in the project's stack.
- `write-css`: Write or review CSS after discovering the project's stack, tokens, targets and conventions.

## Sub-features

none

## Entry points

- `/user-interface:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/user-interface:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `user-interface` and
`<skill>` from Parts. The skill's own `plugins/user-interface/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

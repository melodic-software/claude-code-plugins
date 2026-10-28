# user-experience

The skills of `plugins/user-experience`. Each one is driven with `<plugin-dir>` set to `plugins/user-experience`.

## Parts

- `evaluate`: Plan and run UX evaluations, fair-choice checks and measure selection, evidence-labeled.
- `plan-user-research`: Plan user research and write its instruments, evidence-labeled.
- `setup`: Verify or configure the user-experience plugin for this repository: check probes node and the claude CLI, resolves the ... No plain-words entry.
- `shape`: Detect the app's stage and the project's own evidence, then chain the UX jobs in order.
- `structure`: Shape user flows, information architecture and content structure, evidence-labeled.
- `synthesize`: Synthesize research data into labeled themes, insights, needs, personas or jobs.

## Sub-features

none

## Entry points

- `/user-experience:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/user-experience:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `user-experience` and
`<skill>` from Parts. The skill's own `plugins/user-experience/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# education

The skills of `plugins/education`. Each one is driven with `<plugin-dir>` set to `plugins/education`.

## Parts

- `explain`: Explain any concept or the last response in genuinely plain words.
- `illustrate`: Visual explainer for a concept or codebase topic, record plus interactive page.
- `quiz-me`: Generate a post-change report with a quiz verifying you absorbed the work.
- `setup`: Check the education plugin's userConfig values and the repository's docs/conventions/education.yaml, and write that ... No plain-words entry.
- `teach`: Multi-session learning coach for general topics or repo-grounded concepts. No plain-words entry.

## Sub-features

none

## Entry points

- `/education:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/education:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `education` and
`<skill>` from Parts. The skill's own `plugins/education/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

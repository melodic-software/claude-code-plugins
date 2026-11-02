# review

The skills of `plugins/review`. Each one is driven with `<plugin-dir>` set to `plugins/review`.

## Parts

- `check`: Report whether node resolves and the connected-page Artifact guard is registered. Never installs.
- `code-review`: Org CI code-review lane command for a GitHub pull request.
- `explain-change`: Change digest for a pull request, markdown record plus an interactive view.
- `fanout`: Fan review out across every reviewer surface into one ranked report.
- `quality-gate`: Single-lens review checkpoint routed to the matching reviewer.
- `security-review`: Org CI security-review lane command for a GitHub pull request.
- `setup`: Check or apply the review plugin's repository setup: the standards index and docs/conventions/review.yaml settings. No plain-words entry.

## Sub-features

none

## Entry points

- `/review:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/review:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `review` and
`<skill>` from Parts. The skill's own `plugins/review/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

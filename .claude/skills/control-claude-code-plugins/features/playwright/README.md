# playwright

The skills of `plugins/playwright`. Each one is driven with `<plugin-dir>` set to `plugins/playwright`.

## Parts

- `check`: Report whether playwright-cli and a browser resolve. Never installs.
- `demo-video`: Replay a web flow, render a produced demo video, quality-control it from frames, post it to the PR.
- `playwright`: Live E2E browser automation with disk-written artifacts.
- `setup`: Verify the playwright plugin's runtime prerequisites: the playwright-cli binary and a resolvable browser for this ... No plain-words entry.

## Sub-features

none

## Entry points

- `/playwright:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/playwright:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `playwright` and
`<skill>` from Parts. The skill's own `plugins/playwright/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

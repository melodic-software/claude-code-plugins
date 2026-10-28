# testing

The skills of `plugins/testing`. Each one is driven with `<plugin-dir>` set to `plugins/testing`.

## Parts

- `audit`: Detect tests that cannot fail. Report, gate, or persist.
- `check`: Report whether node and jq resolve for the testing hooks. Never installs.
- `check-visual-parity`: Baseline screenshots before a change, pixel counts against them after.
- `cleanup`: Rewrite, quarantine or delete low-value tests behind a mutation gate, or delete cannot-fail ones.
- `diagnose`: Root-cause failing tests, never retry blindly.
- `plan`: Classify changes by required test type and coverage gaps.
- `run-e2e`: Start the app, drive real flows, capture evidence.
- `setup`: Configure the testing plugin's can't-fail checks for this repository. No plain-words entry.
- `test-value`: Where expected values come from and which tests earn their keep. No slash command.
- `write`: Write and place tests with TDD cadence across ecosystems.

## Sub-features

none

## Entry points

- `/testing:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/testing:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `testing` and
`<skill>` from Parts. The skill's own `plugins/testing/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

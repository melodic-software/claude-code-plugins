# toolchain

The skills of `plugins/toolchain`. Each one is driven with `<plugin-dir>` set to `plugins/toolchain`.

## Parts

- `check`: Build, test, and lint changed files across detected ecosystems.
- `check-prerequisites`: Report whether the tools toolchain declares resolve. Never installs.
- `lint`: Polyglot lint and format checks without a full build.
- `ratchet`: Hold a count in CI with a checked-in ceiling a human merges.
- `setup`: Report or write this repository's tracked .claude/ecosystems/ECOSYSTEM.yaml build, test and lint commands, which /toolchain:check and /toolchain:lint resolve first. No plain-words entry.

## Sub-features

none

## Entry points

- `/toolchain:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/toolchain:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `toolchain` and
`<skill>` from Parts. The skill's own `plugins/toolchain/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

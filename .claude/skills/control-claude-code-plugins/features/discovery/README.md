# discovery

The skills of `plugins/discovery`. Each one is driven with `<plugin-dir>` set to `plugins/discovery`.

## Parts

- `blindspot`: Surface your unknown-unknowns and sharpen the prompt before unfamiliar work.
- `check`: Report whether node resolves and the WebFetch truncation hook is registered. Never installs.
- `explore`: Explore code, history, tests, and config before changing anything.
- `read-docs`: Read an upstream docs page through the shared lookup and cache.
- `report`: The return contract every agent a plugin skill dispatches reports in. No slash command.
- `research`: Multi-source external research with source tiers and a coverage ledger.
- `setup`: Verify the discovery plugin's runtime prerequisites for this session, print the gate allow rules for the operator to paste so the acceptance-gate scripts stop prompting, and write the repository's docs/conventions/discovery.yaml after confirmation. No plain-words entry.
- `trace-intent`: Reconstruct why a thing was built this way, from evidence outside the code.

## Sub-features

none

## Entry points

- `/discovery:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/discovery:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `discovery` and
`<skill>` from Parts. The skill's own `plugins/discovery/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

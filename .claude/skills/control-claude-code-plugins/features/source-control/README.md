# source-control

The skills of `plugins/source-control`. Each one is driven with `<plugin-dir>` set to `plugins/source-control`.

## Parts

- `babysit-loop`: Run one repo's PR queue as a standing merge lane.
- `babysit-prs`: Tiered fleet pass advancing your open PRs.
- `check`: Report whether node and jq resolve for the source-control hooks. Never installs.
- `commit`: Commit with the resolved convention and surgical staging.
- `pull-request`: Full PR lifecycle. Prep, create, monitor CI, address reviews, merge.
- `resolve-conflicts`: Resolve merge and rebase conflicts by recovering both sides' intent.
- `setup`: Configure the source-control plugin. No plain-words entry.
- `worktree`: Create, inspect, and clean git worktrees for parallel sessions.

## Sub-features

none

## Entry points

- `/source-control:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/source-control:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `source-control` and
`<skill>` from Parts. The skill's own `plugins/source-control/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

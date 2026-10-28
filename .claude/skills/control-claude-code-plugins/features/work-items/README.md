# work-items

The skills of `plugins/work-items`. Each one is driven with `<plugin-dir>` set to `plugins/work-items`.

## Parts

- `attend-queue`: Drive escalations to resolution; list held PRs and post-merge failures; hand intake to triage.
- `decompose`: Break a plan into vertical-slice work items with dependencies.
- `onboard-adapter`: Generate a consumer-owned adapter for a tracker this plugin does not bundle.
- `scan-todos`: Sweep source comments for TODO and FIXME markers, resolve or file each.
- `setup`: Verify and configure the work-items plugin for this repo. No plain-words entry.
- `ship`: Route and run a spec container's macro journey. Status, execution shape, next step.
- `track`: Backlog CRUD through the bound tracker. Add, list, close, stats.
- `triage`: Evaluate raw intake through the verified-to-eligible state machine.
- `work`: Auto-select one work item and execute it end-to-end.
- `work-loop`: Drain the backlog as a self-paced autonomous loop.

## Sub-features

none

## Entry points

- `/work-items:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/work-items:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `work-items` and
`<skill>` from Parts. The skill's own `plugins/work-items/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

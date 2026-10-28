# planning

The skills of `plugins/planning`. Each one is driven with `<plugin-dir>` set to `plugins/planning`.

## Parts

- `audit-answers`: Adversarially validate interview answers with fresh-context agents.
- `brainstorm`: Diverge into codebase-grounded candidate approaches before scoping.
- `design`: Resolve types, contracts, and module boundaries before planning.
- `design-handoff`: Gate a finished design and package it for planning.
- `devils-advocate`: Stress-test a plan or the incumbent approach adversarially.
- `draft-goal-condition`: Pick the right autonomy lever and craft a /goal completion condition.
- `interview`: Interview in frontier rounds until the task contract is locked.
- `plan`: Produce a structured implementation plan with an approval gate.
- `prd`: Lock product intent. Problem, users, success metrics. Before planning.
- `questionnaire`: Turn a decision someone else must answer into an async questionnaire.
- `setup`: Verify and configure the planning plugin for this repository. No plain-words entry.
- `wayfind`: Chart a too-big, foggy effort as a decision map worked one decision at a time.

## Sub-features

none

## Entry points

- `/planning:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/planning:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `planning` and
`<skill>` from Parts. The skill's own `plugins/planning/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

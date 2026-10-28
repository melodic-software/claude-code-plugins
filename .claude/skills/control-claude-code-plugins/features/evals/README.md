# evals

The skills of `plugins/evals`. Each one is driven with `<plugin-dir>` set to `plugins/evals`.

## Parts

- `design`: Interview for success criteria and scaffold an eval suite in the consumer repo.
- `methodology`: Answer LLM-evaluation design questions from Anthropic's official guidance.
- `plugin-eval`: Preflight, price, run, and read a plugin eval suite around the CLI.
- `validate`: Static FAIL/WARN check of an eval suite's cases and graders, with no model call.

## Sub-features

none

## Entry points

- `/evals:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/evals:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `evals` and
`<skill>` from Parts. The skill's own `plugins/evals/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

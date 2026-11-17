# review

The skills of `plugins/review`. Each one is driven with `<plugin-dir>` set to `plugins/review`.

## Parts

- `code-review`: Org CI code-review lane command for a GitHub pull request.
- `council`: Configurable reviewer panel chosen per change, with optional fix rounds.
- `explain-change`: Change digest for a pull request, markdown record plus an interactive view.
- `fanout`: Fan review out across every reviewer surface into one ranked report.
- `merge-risk`: Checked merge-risk rating of one pull request with a demote-only flag.
- `quality-gate`: Single-lens review checkpoint routed to the matching reviewer.
- `reviewer-media`: Narrated walkthrough video for a pull request's reviewers, placed in its description.
- `security-review`: Org CI security-review lane command for a GitHub pull request.
- `setup`: Check or apply the review plugin's repository setup: the standards index, docs/conventions/review.yaml settings, and the repository's own design-smell list. No plain-words entry.

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
The action to drive for `fanout` is the default review with no person present, so `<args>` is
`--unattended`: it reviews the checkout's change under the `reproduce_findings` value its
`docs/conventions/review.yaml` sets.

`finding_prover_agent_calls_count` is the number of `tool_use` blocks in the driven session's
`logs` stream-json whose `name` is `Agent` and whose `input.subagent_type` is
`review:finding-prover`; `0` when there are none.

Budget: finding_prover_agent_calls_count | logs

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

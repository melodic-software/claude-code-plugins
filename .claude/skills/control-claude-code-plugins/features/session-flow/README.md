# session-flow

The skills of `plugins/session-flow`. Each one is driven with `<plugin-dir>` set to `plugins/session-flow`.

## Parts

- `audit-friction`: Mine sessions for permission and autonomy friction and end in one decision brief.
- `audit-sessions`: Cross-session audit of transcripts with routed, never-applied findings.
- `check`: Report whether node and jq resolve for the session-flow observer hook. Never installs.
- `clean-stop`: Make everything durable before the machine goes away.
- `continue-in-background`: Delegate the task to a fresh background agent now.
- `find-handoff`: Recover a lost handoff or resume prompt after /clear.
- `handoff`: Write a mid-session save-point for clear-and-resume.
- `keep-going`: Recover after an interruption and continue where work stood.
- `orchestrate`: Arm the session with proactive-orchestration imperatives.
- `orient`: Read-only situation report from durable and off-thread state.
- `reanchor`: Verify working assumptions are still true before building on them.
- `recall`: Topic history from past transcripts, reverts, closed PRs and tracker items.
- `reconcile`: Retire finished off-thread work and square the task ledger.
- `retro`: Structured session retrospective with codified learnings.
- `running-retro`: In-flight retro checkpoint appended to a running ledger.
- `setup`: Verify the session-flow observer's runtime prerequisites and configuration for this machine, and write the repository's docs/conventions/session-flow.yaml after confirmation. No plain-words entry.
- `show-options`: Lay out the skills that fit this moment as a ranked, nothing-hidden menu.
- `tidy-work`: Report, normalize, and clean stale .work memory items. No plain-words entry.
- `workflow`: Navigate the staged dev workflow and suggest the next stage.

## Sub-features

none

## Entry points

- `/session-flow:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/session-flow:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `session-flow` and
`<skill>` from Parts. The skill's own `plugins/session-flow/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

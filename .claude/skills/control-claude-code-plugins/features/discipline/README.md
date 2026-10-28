# discipline

The skills of `plugins/discipline`. Each one is driven with `<plugin-dir>` set to `plugins/discipline`.

## Parts

- `be-ambitious`: Raise a request before work and wait, or deepen finished work and redo it with an outside check. No plain-words entry.
- `do-your-research`: Re-anchor research discipline, then audit and correct the current work.
- `follow-our-standards`: Re-anchor to org engineering standards and audit the work in flight.
- `hold-my-hand`: Standing posture. Phase the work, present one phase at a time, wait for the advancing reply.
- `mind-your-maxims`: Re-anchor cooperative communication and audit recent responses for clarity.
- `pick-for-the-problem`: Re-derive a tool or approach choice from the problem, not habit.
- `point-dont-copy`: Audit for copied content and correct by pointing at the living source.
- `reason-dont-recite`: Challenge decisions coasting on precedent, re-derive from first principles.
- `recheck-against-upstream`: Audit the surface in flight against current official upstream docs.
- `reuse-or-replace`: Reuse the established way or openly replace it, never a silent second way.
- `script-the-deterministic-work`: Script counting, diffing, and transforms instead of eyeballing them.
- `scrutinize-dont-coast`: Re-examine your own recent output through a fresh-context pass.
- `setup`: Validate the discipline plugin's configuration, explain how to change the personal options through Claude Code's plugin configuration prompt, and write the repository file after confirmation. No plain-words entry.
- `sweep-all`: Batch every discipline corrector into one audited re-anchor pass.
- `tighten-your-output`: Tighten prose and code. Fewer words, no semantic loss.
- `use-your-skills`: Map the task to available skills and invoke them instead of reinventing.
- `wait-what`: Re-pitch the message that did not land. Missing context added, plain register, project vocabulary. No plain-words entry.

## Sub-features

- [discipline/tighten-your-output](tighten-your-output/README.md)
- [discipline/wait-what](wait-what/README.md)

## Entry points

- `/discipline:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/discipline:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `discipline` and
`<skill>` from Parts. The skill's own `plugins/discipline/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# animation

The skills of `plugins/animation`. Each one is driven with `<plugin-dir>` set to `plugins/animation`.

## Parts

- `check-prerequisites`: Report whether the tools animation declares resolve. Never installs.
- `learn-style`: Measure a traced clip into a style pack and check new scenes against it.
- `produce`: Brief, boards, approval gate, shots, render, and pack review.
- `rotoscope`: Trace, render, measure and fit a 1:1 replica of a reference animation.
- `setup`: Check-only PASS/FAIL report of the animation plugin's prerequisites (ffmpeg, Node, Chromium, numpy, opencv); installs ... No plain-words entry.

## Sub-features

none

## Entry points

- `/animation:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/animation:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `animation` and
`<skill>` from Parts. The skill's own `plugins/animation/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

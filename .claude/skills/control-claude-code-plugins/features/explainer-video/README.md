# explainer-video

The skills of `plugins/explainer-video`. Each one is driven with `<plugin-dir>` set to `plugins/explainer-video`.

## Parts

- `check`: Report whether Python, ManimCE, ffmpeg and ffprobe are ready. Never installs.
- `produce`: Script, narrate, render and self-check a ManimCE explainer video.

## Sub-features

none

## Entry points

- `/explainer-video:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/explainer-video:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `explainer-video` and
`<skill>` from Parts. The skill's own `plugins/explainer-video/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

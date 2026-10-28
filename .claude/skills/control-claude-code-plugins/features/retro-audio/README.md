# retro-audio

The skills of `plugins/retro-audio`. Each one is driven with `<plugin-dir>` set to `plugins/retro-audio`.

## Parts

- `music`: Render a short chiptune score to a WAV file.
- `sfx`: Render one retro sound effect to a WAV file.

## Sub-features

none

## Entry points

- `/retro-audio:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/retro-audio:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `retro-audio` and
`<skill>` from Parts. The skill's own `plugins/retro-audio/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# speech

The skills of `plugins/speech`. Each one is driven with `<plugin-dir>` set to `plugins/speech`.

## Parts

- `check`: Report each missing speech prerequisite. Never installs.
- `narrate`: Script in, narration.wav and words.json out (kokoro local; elevenlabs optional, third-party).
- `setup`: Set up the speech plugin's text-to-speech prerequisites: check reports Python, espeak-ng, the hook-installed Python ... No plain-words entry.

## Sub-features

none

## Entry points

- `/speech:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/speech:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `speech` and
`<skill>` from Parts. The skill's own `plugins/speech/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

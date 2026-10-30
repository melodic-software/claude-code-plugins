# pixel-art

The skills of `plugins/pixel-art`. Each one is driven with `<plugin-dir>` set to `plugins/pixel-art`.

## Parts

- `animate`: Author, render, and review pixel-art animation cycles and sprite sheets.
- `scene`: Author, render, and review a self-contained HTML pixel-art scene.
- `sprite`: Author, render, and review a static pixel-art sprite.
- `tileset`: Author, render, and review an engine tileset or parallax.
- `ui`: Author, render, and review pixel-art UI skins, icons, and fonts.
- `vfx`: Author, render, and review pixel-art effects and animation cells.

## Sub-features

none

## Entry points

- `/pixel-art:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/pixel-art:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `pixel-art` and
`<skill>` from Parts. The skill's own `plugins/pixel-art/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

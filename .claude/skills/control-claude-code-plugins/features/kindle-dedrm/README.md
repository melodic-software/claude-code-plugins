# kindle-dedrm

The skills of `plugins/kindle-dedrm`. Each one is driven with `<plugin-dir>` set to `plugins/kindle-dedrm`.

## Parts

- `manage`: Manage the Kindle for PC 2.8.0 + Calibre DeDRM workflow for personal-use ebook DRM removal on books the user owns ...
- `setup`: Verify and provision the Kindle for PC 2.8.0 + Calibre DeDRM workflow (Windows only, personal-use, books the user owns). No plain-words entry.

## Sub-features

none

## Entry points

- `/kindle-dedrm:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/kindle-dedrm:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `kindle-dedrm` and
`<skill>` from Parts. The skill's own `plugins/kindle-dedrm/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

# ai-briefing

The skills of `plugins/ai-briefing`. Each one is driven with `<plugin-dir>` set to `plugins/ai-briefing`.

## Parts

- `generate`: Build a source-backed AI industry briefing from official vendor publications, configured RSS feeds, GitHub releases ...
- `setup`: Verify or configure an ai-briefing profile and, only when explicitly requested, install the deterministic HTML/PDF/PPTX ... No plain-words entry.

## Sub-features

none

## Entry points

- `/ai-briefing:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/ai-briefing:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `ai-briefing` and
`<skill>` from Parts. The skill's own `plugins/ai-briefing/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

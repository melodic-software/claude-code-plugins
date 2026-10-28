# songwriting

The skills of `plugins/songwriting`. Each one is driven with `<plugin-dir>` set to `plugins/songwriting`.

## Parts

- `co-write`: Co-writing sessions under the No-Free-Zone protocol and feedback discipline, the Title Game, title generation from an idea, and high-volume option dumps for ONE line or ONE section, with Pat Pattison's methods.
- `diagnose`: Review, audit and rewrite a lyric with Pat Pattison's methods.
- `metaphor`: Generate and diagnose metaphor with Pat Pattison's methods, the three types, the three expressed-identity forms, collision drills, playing in keys, the two metaphor-finder questions, participles, transitive vs intransitive, simile as focus control, and grounded-metaphor diagnosis.
- `meter-prosody`: Make structure serve meaning with Pat Pattison's methods: meter, prosody, section stability and lyric-melody fit.
- `object-writing`: Raw sensory material with Pat Pattison's methods.
- `practice`: Build a songwriting practice habit with Pat Pattison's curriculum, the daily object-writing/craft routine and numbered exercises drawn from all four books.
- `rhyme`: Find and stress-test rhymes with Pat Pattison's discipline.
- `setup`: Configure the songwriting plugin for this repository. No plain-words entry.
- `song-form`: Song structure with Pat Pattison's methods.
- `suno`: Suno AI music prompts (v5.5): style prompts, tagged lyrics, genre templates, troubleshooting, tips, features and genre research.
- `workflow`: Start-here situation router for songwriting with Pat Pattison's methods.

## Sub-features

none

## Entry points

- `/songwriting:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/songwriting:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `songwriting` and
`<skill>` from Parts. The skill's own `plugins/songwriting/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.

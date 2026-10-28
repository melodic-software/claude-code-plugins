# songwriting

The skills of `plugins/songwriting`. Each one is driven with `<plugin-dir>` set to `plugins/songwriting`.

## Parts

- `co-write`: Co-writing sessions under the No-Free-Zone protocol and feedback discipline, the Title Game (chained vowel-cascade ...
- `diagnose`: Review, audit and rewrite a lyric with Pat Pattison's methods: demo review at any stage, full-draft diagnosis, the ...
- `metaphor`: Generate and diagnose metaphor with Pat Pattison's methods, the three types (expressed identity, qualifying, verbal) ...
- `meter-prosody`: Make structure serve meaning with Pat Pattison's methods: meter (scansion, Paradigms I/II/III, Pentad, Goldilocks, the ...
- `object-writing`: Raw sensory material with Pat Pattison's methods: sense-bound object writing (timed dives, the pivot chain, the ...
- `practice`: Build a songwriting practice habit with Pat Pattison's curriculum, the daily object-writing/craft routine and numbered ...
- `rhyme`: Find and stress-test rhymes with Pat Pattison's discipline.
- `setup`: Configure the songwriting plugin for this repository: inventory or scaffold the project-level prompt-template overrides ... No plain-words entry.
- `song-form`: Song structure with Pat Pattison's methods: section identification, forms (AABA, verse/chorus, verse/refrain), the ...
- `suno`: Suno AI music prompts (v5.5): style prompts, tagged lyrics, genre templates, troubleshooting, tips, features and genre ...
- `workflow`: Start-here situation router for songwriting with Pat Pattison's methods: blank page, idea/seed, stuck fragment ...

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

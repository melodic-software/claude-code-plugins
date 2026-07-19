# songwriting

A Claude Code plugin for **songwriting craft** — one cohesive capability covering the two halves of
getting a song written with AI in the loop: writing the lyric well, and prompting Suno to perform it.

The lyric-craft side is decomposed **by concern** into focused skills, each a thin router over a
shared reference corpus. Start with `/songwriting:workflow` if you have a situation ("blank page",
"co-write tonight", "half a song") and it routes you; invoke a concern skill directly when you know
the craft term.

| Skill | Invoke | Answers |
|---|---|---|
| `workflow` | `/songwriting:workflow <action>` | Start-here situation router (11 scenarios), step-by-step coaching dialog, blank-page/idea/fragment starts, the response-filter diagnostic, and going-deeper resources. |
| `rhyme` | `/songwriting:rhyme <action>` | Rhyme generation and stress-testing — identity check, stability tiers, rhyme types, mosaic/multi-word rhyme, worksheets, and the Datamuse lookup supplement. |
| `object-writing` | `/songwriting:object-writing <action>` | Sensory raw material and figurative language — object writing, metaphor (3 types, 8 recipes), cliche repair, and point of view. |
| `meter-prosody` | `/songwriting:meter-prosody <action>` | Sound and motion — scansion/meter, prosody, phrasing, section stability, and lyric-melody alignment. |
| `song-form` | `/songwriting:song-form <action>` | Structure — form and song forms, hook placement, repetition/repainting, verse development, the box model, and bridges. |
| `co-write` | `/songwriting:co-write <action>` | Collaboration and volume — the No-Free-Zone co-write protocol, the Title Game, title generation, and high-volume line/section dumps. |
| `diagnose` | `/songwriting:diagnose <action>` | Review and revise — demo review, full-draft diagnosis, the pre-lock audit checklist, variations, and rewrite. |
| `practice` | `/songwriting:practice <action>` | Habit — the daily craft routine and numbered exercises across all four Pat Pattison books. |
| `suno` | `/songwriting:suno <action>` | Suno v5.5 prompt engineering — style prompts (6-layer formula), tagged lyrics with per-section overrides, 12 genre templates, genre research, troubleshooting, and feature guidance (Voices, Custom Models, Studio). |
| `setup` | `/songwriting:setup` | `check` (default) inventories the project-level prompt-template overrides under `songwriting/templates/pat-pattison/` and reports the effective artifact layout; `apply scaffold <name>` copies a bundled default into an override, `apply remove <name>` clears one. Idempotent; scaffold only the templates you intend to customize. |

The lyric-craft skills and `suno` are deliberately paired: the lyric-craft skills develop the lyric;
`/songwriting:suno` formats the finished lyric for Suno's syntax. Each works standalone.

## Method content and the author seam

Every lyric-craft skill is **concern-scoped and author-neutral** — the skill is the stable interface
(what you invoke); the opinionated method behind it is content. Today that method is **Pat
Pattison's**, held once under `context/pat-pattison/` (the full reference corpus, its templates, the
Datamuse script, and the mandatory response filter). A future author's method for the same concern
plugs in at `context/<author>/` without changing the concern skills — the concern skills are open for
extension, closed for modification.

Every craft output first runs the applicable section of the response filter
(`context/pat-pattison/research/response-filter.md`) — the gate that replaces generic LLM defaults
(perfect rhymes, abstract telling, single-winner picks) with Pat's craft.

## Artifacts

Per-song work persists under your project root at `songwriting/songs/<slug>/` by default
(`LYRIC.md`, `BRIEF.md`, `ideation/`, `variations/`, `worksheets/`, `decisions/`), with daily
practice (`songwriting/practice/<YYYY>/<date>.md`), cross-song research, and shared worksheets in
sibling `songwriting/` folders. If your project's own `CLAUDE.md` or rules define a different
songwriting layout, that layout wins.

You can override any prompt template without forking the plugin: a file at
`songwriting/templates/pat-pattison/<name>.md` in your project takes precedence over the bundled
default.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install songwriting@melodic-software
```

## Configuration

This plugin has no `userConfig`. Its inputs are conversational (the action and material you pass),
plus the project-level template override and layout override described above. Run `/songwriting:setup`
to inventory your overrides and confirm your artifact layout (the read-only `check` default), then
`/songwriting:setup apply scaffold <name>` to scaffold a template override from its bundled default —
idempotent and safe to re-run to reconfigure.

## Requirements

None beyond Claude Code for the core skills. The optional Datamuse rhyme/vocabulary helper
(`context/pat-pattison/scripts/datamuse.sh`, used by `/songwriting:rhyme` as a supplement) needs
`bash`, `curl`, and `jq`, and calls the free, no-auth [Datamuse API](https://www.datamuse.com/api/)
— the only network egress in the plugin. Without those tools the skill degrades gracefully to
internal rhyme generation.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository. Pat Pattison's books are cited as methodology
sources; the plugin contains distilled craft guidance and short verified anchor quotes, not book
text.

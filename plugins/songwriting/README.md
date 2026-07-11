# songwriting

A Claude Code plugin for **songwriting craft** — one cohesive capability covering the two halves of
getting a song written with AI in the loop: writing the lyric well, and prompting Suno to perform it.

It ships **two skills**:

| Skill | Invoke | Answers |
|---|---|---|
| `pat-pattison` | `/songwriting:pat-pattison <action>` | Lyric craft — writing, rewriting, rhyming, diagnosis, object writing, metaphor, meter/prosody, song form, point of view, co-writing, and daily practice, applying Pat Pattison's methods (all 4 books plus Berklee/Coursera materials) through an action router and a mandatory response filter. |
| `suno` | `/songwriting:suno <action>` | Suno v5.5 prompt engineering — style prompts (6-layer formula), tagged lyrics with per-section style overrides, 12 genre templates, genre research, troubleshooting, and feature guidance (Voices, Custom Models, Studio). |

The pair is deliberate: `/songwriting:pat-pattison` develops the lyric; `/songwriting:suno` formats
the finished lyric for Suno's syntax. Each works standalone.

## Artifacts

Per-song work persists under your project root at `songwriting/songs/<slug>/` by default
(`LYRIC.md`, `BRIEF.md`, `ideation/`, `variations/`, `worksheets/`, `decisions/`), with daily
practice, cross-song research, and shared worksheets in sibling `songwriting/` folders. If your
project's own `CLAUDE.md` or rules define a different songwriting layout, that layout wins.

You can override any `pat-pattison` prompt template without forking the plugin: a file at
`songwriting/templates/pat-pattison/<name>.md` in your project takes precedence over the bundled
default.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install songwriting@melodic-software
```

## Configuration

This plugin has no `userConfig`. Its inputs are conversational (the action and material you pass),
plus the project-level template override and layout override described above.

## Requirements

None beyond Claude Code for the core skills. The optional Datamuse rhyme/vocabulary helper
(`scripts/datamuse.sh`, used by `/songwriting:pat-pattison` rhyme actions as a supplement) needs
`bash`, `curl`, and `jq`, and calls the free, no-auth [Datamuse API](https://www.datamuse.com/api/)
— the only network egress in the plugin. Without those tools the skill degrades gracefully to
internal rhyme generation.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository. Pat Pattison's books are cited as methodology
sources; the plugin contains distilled craft guidance and short verified anchor quotes, not book
text.

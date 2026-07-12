# Cross-Skill Routing Index

Which `/songwriting` skill (and action) answers a given request. The per-skill action tables live in
each skill's own `SKILL.md`; this file is the cross-skill map the `workflow` orchestrator loads when
routing is ambiguous or when surfacing the menu to the user.

Method content is Pat Pattison's. Skills are concern-scoped and author-neutral; his method is the
content under `context/pat-pattison/`.

## Skills at a glance

| Skill | Owns |
| --- | --- |
| `/songwriting:workflow` | situation routing (11 scenarios), coaching dialog, blank-page/idea/fragment starts, response-filter diagnostic, going-deeper resources |
| `/songwriting:rhyme` | rhyme generation, rhyme types, mosaic, worksheets, Datamuse lookup |
| `/songwriting:object-writing` | object writing, metaphor, cliche repair, point of view |
| `/songwriting:meter-prosody` | scansion/meter, prosody, phrasing, stability, lyric-melody fit |
| `/songwriting:song-form` | form, song forms, hook, repetition, verse, bridge, box model |
| `/songwriting:co-write` | co-write protocol, Title Game, titles, high-volume line/section dumps |
| `/songwriting:diagnosis` | demo review, full-draft diagnosis, pre-lock audit, variations, rewrite |
| `/songwriting:daily-practice` | daily curriculum, numbered exercises |
| `/songwriting:suno` | Suno v5.5 prompt formatting (separate capability) |

## Quick Decision Guide

| User asks | Route |
| --- | --- |
| "I want to write a new song." | `/songwriting:workflow` → Scenario 1 |
| "I have nothing — just want to write something." | `/songwriting:workflow brainstorm` (Scenario 8) |
| "I have an image / phrase / feeling — no title." | `/songwriting:workflow idea` (Scenario 9) |
| "This line / verse / fragment is stuck." | `/songwriting:workflow fragment` (Scenario 10) |
| "This demo is partway done — what's missing?" | `/songwriting:diagnosis demo` (Scenario 11) |
| "Review my full draft." | `/songwriting:diagnosis diagnose` (or `/songwriting:workflow` Scenario 2 / 6) |
| "I have a title — what next?" | `/songwriting:workflow` Scenario 3, then `/songwriting:co-write title` + `/songwriting:rhyme worksheet` |
| "I have a melody for these lyrics." | `/songwriting:meter-prosody align-melody` (Scenario 4) |
| "Co-write tonight." | `/songwriting:co-write` + `/songwriting:co-write title-game` (Scenario 5) |
| "Daily practice plan." | `/songwriting:daily-practice` (Scenario 7) |
| "Is this verse stable or unstable?" | `/songwriting:meter-prosody stability` |
| "Find rhymes for X that aren't cliche." | `/songwriting:rhyme` (internal first), supplement with `/songwriting:rhyme datamuse` if needed |
| "Syllable count of this line." | `/songwriting:rhyme datamuse` |
| "Why does this rhyme feel weak?" | `/songwriting:rhyme` |
| "Make this verse less abstract." | `/songwriting:object-writing` + `/songwriting:diagnosis rewrite` |
| "Give me a 90-second writing prompt." | `/songwriting:object-writing` or `/songwriting:daily-practice` |
| "I need a metaphor for trust." | `/songwriting:object-writing metaphor` or `metaphor-recipe` |
| "Generate eight metaphor options for X." | `/songwriting:object-writing metaphor-recipe` |
| "Should this be like or is?" | `/songwriting:object-writing metaphor` |
| "Scan this line." | `/songwriting:meter-prosody meter` |
| "Can this be common meter?" | `/songwriting:meter-prosody meter` |
| "My chorus does not land." | `/songwriting:song-form hook` + `/songwriting:meter-prosody` |
| "My second verse repeats the first." | `/songwriting:song-form box-model` + `repetition` |
| "Is this a verse/chorus or AABA song?" | `/songwriting:song-form song-forms` |
| "Where should the title go?" | `/songwriting:song-form hook` |
| "Generate title candidates from this idea." | `/songwriting:co-write title` or `/songwriting:workflow idea` |
| "Title Game / vowel cascade." | `/songwriting:co-write title-game` |
| "Write me a bridge." | `/songwriting:song-form bridge` |
| "What goes in verse 2 / 3?" | `/songwriting:song-form box-model` |
| "Audit this line before I lock it." | `/songwriting:diagnosis audit` |
| "Give me 5 versions of line 3." | `/songwriting:diagnosis variations` |
| "This line sounds cliched." | `/songwriting:object-writing cliche` |
| "Who is speaking in this lyric?" | `/songwriting:object-writing pov` |
| "My lyric and melody don't fit." | `/songwriting:meter-prosody align-melody` |
| "There's a greedy spot in line 2." | `/songwriting:meter-prosody align-melody` + `prosody` |
| "Run me a numbered exercise." | `/songwriting:daily-practice exercise` |
| "How do I structure a co-writing session?" | `/songwriting:co-write` |
| "Coursera / Berklee / Pat's columns / podcasts." | `/songwriting:workflow beyond-books` |
| "Rhyme this proper noun / brand / place." | `/songwriting:rhyme mosaic` |
| "I need mosaic rhymes / rhymes like Eminem." | `/songwriting:rhyme mosaic` |
| "Give me 30 options for this line." | `/songwriting:co-write line-brainstorm` |
| "Brainstorm the whole chorus / verse / bridge." | `/songwriting:co-write section-brainstorm` |
| "Walk me through writing this song step by step." | `/songwriting:workflow coach` |
| "I have an idea but I don't know where to start." | `/songwriting:workflow coach` |
| "Review the rhyme list this AI just gave me." | `/songwriting:workflow filter` (applies response-filter §1) |
| "Did my critique do Pat's craft right?" | `/songwriting:workflow filter` (applies §3) |

## Sample Invocations

```text
/songwriting:workflow
/songwriting:workflow brainstorm
/songwriting:workflow idea "image of an empty diner at 3am"
/songwriting:workflow fragment "the streetlight talks back"
/songwriting:workflow coach
/songwriting:workflow filter "<paste AI-generated rhyme list to audit>"
/songwriting:workflow beyond-books
/songwriting:rhyme
/songwriting:rhyme types
/songwriting:rhyme mosaic "Texas"
/songwriting:rhyme worksheet "last call at the Moonlight"
/songwriting:rhyme datamuse syllables disappointment
/songwriting:object-writing 90 seconds hotel bar
/songwriting:object-writing metaphor-recipe trust
/songwriting:meter-prosody meter "I woke up under a borrowed sky"
/songwriting:meter-prosody stability chorus
/songwriting:meter-prosody align-melody "<lyric>" "<melody description>"
/songwriting:song-form song-forms
/songwriting:song-form bridge
/songwriting:song-form box-model
/songwriting:co-write
/songwriting:co-write title "small town funeral"
/songwriting:co-write title-game
/songwriting:co-write line-brainstorm "<paste line>"
/songwriting:co-write section-brainstorm chorus
/songwriting:diagnosis diagnose "<paste verse>"
/songwriting:diagnosis demo "<paste any-stage lyric>"
/songwriting:diagnosis audit "<paste line or section>"
/songwriting:diagnosis variations "<paste line>"
/songwriting:daily-practice
/songwriting:daily-practice exercise 4.6
```

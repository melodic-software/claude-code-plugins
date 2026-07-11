# Action Routing — Full Tables

Full Scenario routing + Craft-term routing + Quick Decision Guide for
`/pat-pattison`. SKILL.md body keeps the summary; this file carries the
detail for progressive disclosure.

## Scenario routing (situation-first)

| Action | Use when the user describes | Load |
| --- | --- | --- |
| `workflow` | brand new song / existing song / from a title / to a melody / co-write / diagnose-only / daily habit / brainstorm / idea / fragment / demo at any stage | [workflows](workflows.md) — picks the scenario chain (11 scenarios) |
| `brainstorm` | "blank page", "no idea", "starting cold", "give me anything", "I want to write but I don't know what" | [brainstorm](brainstorm.md), [templates/brainstorm-opener](../templates/brainstorm-opener.md) |
| `idea` | "I have an idea / image / phrase / feeling but no title", "what title comes from this" | [idea-to-title](idea-to-title.md), [templates/idea-to-title-prompt](../templates/idea-to-title-prompt.md), [hook](hook.md) "title generation", [object-writing](object-writing.md) |
| `fragment` | "I have this line / hook / half-verse — won't grow", "this phrase keeps coming back" | [fragment-development](fragment-development.md), [templates/fragment-development-prompt](../templates/fragment-development-prompt.md), [verse-development](verse-development.md), [object-writing](object-writing.md) |
| `demo` | "review this demo", "where do I take this", "what's missing here", "lyric is partway done" | [demo-review](demo-review.md), [templates/demo-review-prompt](../templates/demo-review-prompt.md), [workflows](workflows.md) Scenario 11 |
| `diagnose` | "what's wrong with my song", "review my draft", "is this any good" (assumes near-complete draft) | [five compositional elements](five-compositional-elements.md), [stable unstable](stable-unstable-meta.md), [prosody](prosody.md) |
| `stability` | "is this verse stable or unstable", "does my song feel right", section-level prosody scan | [stable unstable](stable-unstable-meta.md) |
| `align-melody` | "my words don't fit the music", "set lyrics to this tune", roadmap problems, greedy spots | [lyric-melodic roadmaps](lyric-melodic-roadmaps.md), [phrasing](phrasing.md), [prosody](prosody.md) |
| `title` | "I have an idea but no title", "title candidates for X", title generation | [hook](hook.md) "title generation", [idea-to-title](idea-to-title.md), [templates/title-generation-prompt](../templates/title-generation-prompt.md) |
| `title-game` | "Title Game", "Pat's title cascade", "10 titles fast", "vowel-chain titles", co-write warmup | [title-game](title-game.md), [templates/title-game-prompt](../templates/title-game-prompt.md), [co-writing](co-writing.md) |
| `co-write-protocol` | "starting a co-write session", "co-write rules", "no-free-zone" | [co-writing](co-writing.md), [templates/co-write-session-opener](../templates/co-write-session-opener.md) |
| `audit` | "line-by-line review", "pre-lock checklist", "audit before I commit", "should this lock" | [audit-checklist](audit-checklist.md), [templates/audit-checklist-prompt](../templates/audit-checklist-prompt.md) |
| `variations` | "give me 5 versions of this line", "different POV / image / vowel", "alternate this" | [variations](variations.md), [templates/variations-prompt](../templates/variations-prompt.md) |
| `line-brainstorm` | "30 alternatives for this line", "more end-line words", "lots of swaps", "what could go here" — HIGH VOLUME pre-revision dump for ONE line | [line-brainstorm](line-brainstorm.md), [templates/line-brainstorm-prompt](../templates/line-brainstorm-prompt.md), [mosaic-rhyme](mosaic-rhyme.md) |
| `section-brainstorm` | "more options for the chorus", "what could this verse say", "high volume options for this section" — line-brainstorm per line + stability profile + hot-spot map | [line-brainstorm](line-brainstorm.md) Scope B, [box-model](box-model.md), [audit-checklist](audit-checklist.md) |
| `coach` | "guide me", "walk me through", "help me think", "where do I start", "what next" — dynamic step-by-step dialog | [coaching-protocol](coaching-protocol.md), [workflows](workflows.md) |
| `filter` | "apply Pat's filter to this", "review my AI-generated rhyme list", "is this passing the discipline" — diagnostic mode | [response-filter](response-filter.md) |

## Craft-term routing (concept-first)

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `rhyme` | rhyme choice, rhyme stability, rhyme types, family rhyme, mosaic rhyme | [rhyme-generation](rhyme-generation.md) PRIMARY, [rhyme fundamentals](rhyme-fundamentals.md), [rhyme types](rhyme-types.md), [mosaic-rhyme](mosaic-rhyme.md), [rhyme strategy](rhyme-strategy.md), [rhyme sonic bonding](rhyme-sonic-bonding.md) |
| `rhyme-generation` | the internal rhyme-search discipline; identity check; tier walk; vowel triangle; world vocabulary; mosaic tier | [rhyme-generation](rhyme-generation.md) |
| `mosaic` | "mosaic rhyme", "multi-word rhymes", "rhyme this proper noun", "cross-part-of-speech rhymes", "rhyme like Eminem", "I need rhymes for [polysyllabic / proper noun / rare word]" | [mosaic-rhyme](mosaic-rhyme.md), [rhyme-generation](rhyme-generation.md) Step 3b |
| `datamuse` | "live rhyme lookup", "syllable count of X", "synonyms via API", "semantic field for X" — supplemental data | [ai-tools](ai-tools.md), [scripts/datamuse.sh](../scripts/datamuse.sh) |
| `worksheet` | a rhyme worksheet from a title, theme, section, or draft | [rhyme worksheets](rhyme-worksheets.md), [rhyme dictionary practice](rhyme-dictionary-practice.md), [templates/worksheet-prompt](../templates/worksheet-prompt.md) |
| `rhyme-dictionary` | how to search a rhyming dictionary or avoid identities | [rhyme dictionary practice](rhyme-dictionary-practice.md), [rhyme spotlight and connection](rhyme-spotlight-connection.md) |
| `meter` | scansion, tetrameter, common meter, stress, Paradigms I/II/III, Pentad, Goldilocks, "into" rule, In Memoriam quatrain, pitch-stress | [meter](meter.md) |
| `prosody` | whether structure supports meaning, motion, greedy spots, tone-of-voice | [prosody](prosody.md), [form](form.md), [meter](meter.md), [rhyme strategy](rhyme-strategy.md), [stable unstable](stable-unstable-meta.md) |
| `form` | verse, chorus, bridge, balance, section contrast, candy bar rewrite | [form](form.md), [section building](section-building.md), [song forms](song-forms.md) |
| `song-forms` | AABA, verse/chorus, verse/refrain, bridge validity, four-times-a-lot risk, third-system risk, *Essential Guide to Lyric Form and Structure* (1991) worked examples | [song forms](song-forms.md), [song-forms-examples](song-forms-examples.md), [hook](hook.md), [repetition](repetition.md) |
| `hook` | title placement, hook hot spots (section + phrase level), hook rhythm, targeting | [hook](hook.md), [form](form.md) |
| `object-writing` | sensory writing, showing instead of telling, raw material | [object writing](object-writing.md), [templates/object-writing-prompt](../templates/object-writing-prompt.md) |
| `metaphor` | metaphor, simile, collision drills, linking qualities, productive ambiguity, transitive/intransitive verbal | [metaphor](metaphor.md), [templates/metaphor-collision-prompt](../templates/metaphor-collision-prompt.md) |
| `metaphor-recipe` | 8 named metaphor moves to generate options from a subject | [metaphor](metaphor.md) "8 recipes", [templates/metaphor-recipe-prompt](../templates/metaphor-recipe-prompt.md) |
| `daily` | a daily craft prompt or practice curriculum | [daily practice](daily-practice.md), [templates/object-writing-prompt](../templates/object-writing-prompt.md), [templates/metaphor-collision-prompt](../templates/metaphor-collision-prompt.md) |
| `exercise` | a numbered exercise from *Essential Guide to Lyric Form and Structure* (1991) (Ex 1-44 structural), *Songwriting Without Boundaries* (2011) (Days 1-56 curriculum), or *Essential Guide to Rhyming* (2014) (Chapter 1-9 rhyme worksheets) | [exercises](exercises.md) |
| `cliche` | cliche phrase, cliche image, stale metaphor, cliche rhyme | [cliche](cliche.md), [worksheets](worksheets.md), [metaphor](metaphor.md) |
| `repetition` | chorus repetition, repainting, stagnant repeats, You-I-We / Past-Present-Future, hidden questions/commands | [repetition](repetition.md), [box-model](box-model.md), [form](form.md), [song forms](song-forms.md) |
| `verse` | second verse problems, travelogues, verse development, power positions, trigger lines | [verse development](verse-development.md), [box-model](box-model.md), [repetition](repetition.md), [object writing](object-writing.md) |
| `bridge` | "write me a bridge", "do I need a bridge", bridge as restatement, three bridge functions, AABA homecoming | [bridge](bridge.md), [templates/bridge-writing-prompt](../templates/bridge-writing-prompt.md), [form](form.md), [song-forms](song-forms.md) |
| `box-model` | verse division of labor, second-verse stagnation, what goes in verse 2 / 3, You-I-We, Past-Present-Future | [box-model](box-model.md), [repetition](repetition.md), [verse-development](verse-development.md) |
| `pov` | first/second/third person, direct address, dialogue, pronoun consistency, close-up vs middle distance | [point of view](point-of-view.md) |
| `process` | full writing workflow, revisions, trigger lines | [process](process.md), [worksheets](worksheets.md), [co-writing](co-writing.md) |
| `co-write` | co-writing session rules and feedback discipline | [co-writing](co-writing.md), [process](process.md), [title-game](title-game.md) |
| `rewrite` | a lyric critique or rewrite using Pat's checklist | Start with [stable unstable](stable-unstable-meta.md), [five compositional elements](five-compositional-elements.md), [prosody](prosody.md), [object writing](object-writing.md), [rhyme strategy](rhyme-strategy.md), [cliche](cliche.md); add others as needed |
| `beyond-books` | Coursera / Berklee Online courses, patpattison.com columns, podcasts, workshops, famous students, "how do I go deeper" | [beyond-books](beyond-books.md) |

## Quick Decision Guide

| User asks | Route |
| --- | --- |
| "I want to write a new song." | `workflow` → Scenario 1 |
| "I have nothing — just want to write something." | `brainstorm` (Scenario 8) |
| "I have an image / phrase / feeling — no title." | `idea` (Scenario 9) |
| "This line / verse / fragment is stuck." | `fragment` (Scenario 10) |
| "This demo is partway done — what's missing?" | `demo` (Scenario 11) |
| "Review my full draft." | `workflow` → Scenario 2 or 6, or `diagnose` |
| "I have a title — what next?" | `workflow` → Scenario 3, then `title` + `worksheet` |
| "I have a melody for these lyrics." | `workflow` → Scenario 4, then `align-melody` |
| "Co-write tonight." | `workflow` → Scenario 5, then `co-write-protocol` + `title-game` |
| "Daily practice plan." | `workflow` → Scenario 7, then `daily` |
| "Is this verse stable or unstable?" | `stability` |
| "Find rhymes for X that aren't cliche." | `rhyme-generation` (internal first), supplement with `datamuse` if needed |
| "Syllable count of this line." | `datamuse syllables` |
| "Why does this rhyme feel weak?" | `rhyme` |
| "Make this verse less abstract." | `object-writing` + `rewrite` |
| "Give me a 90-second writing prompt." | `object-writing` or `daily` |
| "I need a metaphor for trust." | `metaphor` or `metaphor-recipe` |
| "Generate eight metaphor options for X." | `metaphor-recipe` |
| "Should this be like or is?" | `metaphor` |
| "Scan this line." | `meter` |
| "Can this be common meter?" | `meter` |
| "My chorus does not land." | `prosody` + `form` + `hook` + `stability` |
| "My second verse repeats the first." | `verse` + `box-model` + `repetition` |
| "Is this a verse/chorus or AABA song?" | `song-forms` |
| "Where should the title go?" | `hook` |
| "Generate title candidates from this idea." | `title` or `idea` |
| "Title Game / vowel cascade." | `title-game` |
| "Write me a bridge." | `bridge` |
| "What goes in verse 2 / 3?" | `box-model` |
| "Audit this line before I lock it." | `audit` |
| "Give me 5 versions of line 3." | `variations` |
| "This line sounds cliched." | `cliche` |
| "Who is speaking in this lyric?" | `pov` |
| "My lyric and melody don't fit." | `align-melody` |
| "There's a greedy spot in line 2." | `align-melody` + `prosody` |
| "Run me a numbered exercise." | `exercise` |
| "How do I structure a co-writing session?" | `co-write` or `co-write-protocol` |
| "Coursera / Berklee / Pat's columns / podcasts." | `beyond-books` |
| "Rhyme this proper noun / brand / place." | `mosaic` (proper nouns are mosaic-territory) |
| "I need mosaic rhymes / rhymes like Eminem." | `mosaic` |
| "Give me 30 options for this line." | `line-brainstorm` |
| "Brainstorm the whole chorus / verse / bridge." | `section-brainstorm` |
| "Walk me through writing this song step by step." | `coach` |
| "I have an idea but I don't know where to start." | `coach` → `workflow` |
| "Review the rhyme list this AI just gave me." | `filter` (apply response-filter §1) |
| "Did my critique do Pat's craft right?" | `filter` (apply §3) |

## Sample Invocations

```text
/pat-pattison workflow brand-new-song
/pat-pattison brainstorm
/pat-pattison idea "image of an empty diner at 3am"
/pat-pattison fragment "the streetlight talks back"
/pat-pattison demo "<paste any-stage lyric>"
/pat-pattison diagnose "<paste verse>"
/pat-pattison stability chorus
/pat-pattison align-melody "<lyric>" "<melody description>"
/pat-pattison title "small town funeral"
/pat-pattison title-game
/pat-pattison metaphor-recipe trust
/pat-pattison co-write-protocol
/pat-pattison audit "<paste line or section>"
/pat-pattison variations "<paste line>"
/pat-pattison bridge
/pat-pattison box-model
/pat-pattison datamuse rhyme stranger
/pat-pattison datamuse syllables disappointment
/pat-pattison exercise 4.6
/pat-pattison rhyme types
/pat-pattison rhyme-generation
/pat-pattison mosaic "Texas"
/pat-pattison mosaic "silence"
/pat-pattison worksheet "last call at the Moonlight"
/pat-pattison object-writing 90 seconds hotel bar
/pat-pattison meter "I woke up under a borrowed sky"
/pat-pattison line-brainstorm "<paste line>"
/pat-pattison section-brainstorm chorus
/pat-pattison coach
/pat-pattison filter "<paste AI-generated rhyme list to audit>"
/pat-pattison rewrite "..."
/pat-pattison beyond-books
```

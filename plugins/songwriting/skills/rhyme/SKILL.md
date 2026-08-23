---
description: "Find and stress-test rhymes with Pat Pattison's discipline — identity check, stability-tier walk, vowel triangle, song-world vocabulary, mosaic/multi-word rhyme, cliche scan. Internal generation is primary (8-15 labeled candidates, never a single winner); the Datamuse API supplements for breadth/syllables/semantic field. Use when: 'rhyme this', 'find rhymes for X', 'why does this rhyme feel weak', 'mosaic rhyme', 'rhyme this proper noun', 'rhyme like Eminem', 'syllable count of X', 'rhyme worksheet'. For meter/scansion use /songwriting:meter-prosody; for line-volume dumps use /songwriting:co-write line-brainstorm."
argument-hint: "[action] [args] (e.g., /songwriting:rhyme, /songwriting:rhyme mosaic \"Texas\", /songwriting:rhyme worksheet) — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Before emitting any rhyme suggestion or rhyme list, run **§1 Rhyme suggestion filter** of
[response-filter](../../context/pat-pattison/research/response-filter.md). NAME each box's
pass / fail / skip-with-reason (aloud or in reasoning), correct before emission. Skips are valid;
silent skips are not. Without the filter, generic LLM defaults — perfect rhymes, predictable
end-lines, single-winner picks — ship instead of Pat's craft.

## Purpose

Rhyme choice, rhyme stability, rhyme types, family/additive/subtractive/assonance/consonance,
mosaic (multi-word) rhyme, and rhyme worksheets. Internal Pat-framed generation is PRIMARY; the
live Datamuse lookup supplements only for vocabulary breadth, syllable verification, or
semantic-field mining.

Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`; a future
author's method plugs in at `context/<author>/` without changing this skill — the author seam per
the plugin-root `../../README.md` "Method content and the author seam".

## Action Router

`/songwriting:rhyme <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → generate rhymes for the word/line in context (the `rhyme` default).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `rhyme` (default) | rhyme choice, rhyme stability, rhyme types, family rhyme | [rhyme-generation](../../context/pat-pattison/research/rhyme-generation.md) PRIMARY, [rhyme-fundamentals](../../context/pat-pattison/research/rhyme-fundamentals.md), [rhyme-types](../../context/pat-pattison/research/rhyme-types.md), [rhyme-strategy](../../context/pat-pattison/research/rhyme-strategy.md), [rhyme-sonic-bonding](../../context/pat-pattison/research/rhyme-sonic-bonding.md) |
| `mosaic` | multi-word rhymes, proper nouns, cross-part-of-speech, "rhyme like Eminem", polysyllabic/rare words | [mosaic-rhyme](../../context/pat-pattison/research/mosaic-rhyme.md), [rhyme-generation](../../context/pat-pattison/research/rhyme-generation.md) Step 3b |
| `types` | the rhyme taxonomy and stability tiers | [rhyme-types](../../context/pat-pattison/research/rhyme-types.md) |
| `datamuse` | live rhyme lookup, syllable count, synonyms/semantic field via API — supplemental | [ai-tools](../../context/pat-pattison/research/ai-tools.md), `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/scripts/datamuse.sh` |
| `worksheet` | a rhyme worksheet from a title, theme, section, or draft | [rhyme-worksheets](../../context/pat-pattison/research/rhyme-worksheets.md), [rhyme-dictionary-practice](../../context/pat-pattison/research/rhyme-dictionary-practice.md), [templates/worksheet-prompt](../../context/pat-pattison/templates/worksheet-prompt.md) |
| `dictionary` | how to search a rhyming dictionary or avoid identities | [rhyme-dictionary-practice](../../context/pat-pattison/research/rhyme-dictionary-practice.md), [rhyme-spotlight-connection](../../context/pat-pattison/research/rhyme-spotlight-connection.md) |
| `strategy` | which rhyme type/position serves the section's motion and meaning | [rhyme-strategy](../../context/pat-pattison/research/rhyme-strategy.md), [rhyme-sonic-bonding](../../context/pat-pattison/research/rhyme-sonic-bonding.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §1 before any rhyme output.
- Load [rhyme-generation](../../context/pat-pattison/research/rhyme-generation.md) FIRST for any
  rhyme request. Apply the discipline — identity check (pre-vowel consonants MUST differ; identity
  is NOT rhyme), vowel-FIELD walk (Step 1b — the source word's own coda is ONE row of the field,
  not the search), stability-tier walk, vowel triangle, song's-world vocabulary, cliche scan — to
  internal vocabulary. Surface 8-15 labeled candidates across tiers, never a single winner.
- Use [ai-tools](../../context/pat-pattison/research/ai-tools.md) (Datamuse) only as a supplement
  for vocabulary breadth, syllable verification, or semantic-field mining. Internal generation is
  PRIMARY; Datamuse supplements. The script degrades gracefully when `bash`/`curl`/`jq` are absent.
- Proper nouns and polysyllabic/rare words are mosaic territory — route to `mosaic`.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Boundary — what this skill must NOT emit

This skill surfaces rhyme candidates and stress-tests them. It does not decide, and it does not
write the line the rhyme lands in.

| If you are about to emit | STOP and route to |
| --- | --- |
| A finished lyric line built around a chosen rhyme | `/songwriting:co-write` line-brainstorm |
| A single winning rhyme presented as the answer | nothing — surface the labeled menu and let the writer pick by emotional intent |
| A structural judgement about where the rhyme sits | `/songwriting:song-form` |
| A claim that a candidate scans | `/songwriting:meter-prosody` |

Three failures belong to this skill specifically and are caught nowhere downstream: a rhyme list
that is all-perfect, all-single-word, and all-same-part-of-speech; a "mosaic" list whose entries
reuse the source word with a prefix (identity in disguise); and a tier-labeled, mosaic-complete
list whose every entry still sits on the source word's own coda — a column sweep, not a walk of
the stressed vowel's field. §1 of the response filter names all three fail signatures — run it
rather than recalling it.

## Related skills

- Scansion, stress, meter paradigms → `/songwriting:meter-prosody meter`
- High-volume swaps for ONE line (end-line × content × internal × image × whole-line) →
  `/songwriting:co-write line-brainstorm`
- Cliche repair for images/metaphors → `/songwriting:object-writing cliche`

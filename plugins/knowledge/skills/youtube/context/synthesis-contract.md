# YouTube watch — synthesis contract

SSOT for what belongs in `key-frames/frames/`. Applies to any `/youtube watch` slice. Cite by heading; do not duplicate floors from `quality-gates.md`.

## Value test

Promote a frame only when it **closes a gap** the transcript and research do not — multimodal evidence for repo-relevant analysis. Not limited to code, diagrams, URLs, or metrics; judgment allowed with manifest justification.

**Reject:** talking-head-only, title-card-only, content fully in transcript or research/Google, duplicate-of-deck-slide when deck fetched, unreadable, mislabeled.

**Sparse is OK.** No quota filler. Zero frames in a session is rare and requires documented deep vision inspect.

## Vision-gated promote

Nothing copies into `frames/` until a vision pass outputs:

1. **Verdict** — promote or reject (reason)
2. **Semantic filename** — kebab-case describing **on-screen content**
3. **Gap note** — what the transcript misses

**Forbidden filenames:** `at-*`, `scene_NNNN`, `anchor_*`, numeric-only, collision suffixes (`-2`, `-2-3`).

## Staged deck-first harvest

```text
run-watch (metadata harvest → harvested-links.json)
  → deck pass A: fetch deck-candidate URLs from metadata/chapters
  → source/deck-inventory.md + source/decks/<session-slug>/
  → vision pass 1 with deck inventory in context
  → merge on-screen URLs → deck pass B for newly discovered decks
  → re-filter remaining sheets when deck B lands
  → vision passes 2–3; promote only non-deck gaps + exceptions
```

**Deck-covered static slides:** triage `skip` (cite deck path). **Still promote:** live demo, code, URL not in deck, deck download failed.

## Artifact layout (vertical slice)

| Kind | Path | Citations |
| --- | --- | --- |
| Slide decks | `source/decks/<session-slug>/` | `source/deck-inventory.md` |
| Other downloads | `source/attachments/<kind>/` | `research/sources.md` |
| URLs (typed) | `source/harvested-links.json` | README, RESEARCH |
| GitHub repos | `harvested-links` + optional `harvested-repo-analysis.json` | research clusters |
| Synthesis PNGs | `key-frames/frames/` | `key-frames-manifest.md` |

`synthesis/` is PNGs only — not markdown, decks, or link lists.

## Verify-script stance

**Quality gates block** completion (semantic names, audit, triage coverage). **Count floors warn-only** — do not promote junk to satisfy `synthesis-count-floor`.

---
bump: patch
---

### Changed

- Five songwriting eval graders now accept forms real runs used and the graders rejected: `ran-syllable-count` takes a `datamuse.sh` path held in a shell variable and run as `$S syllables`; `raw-count-not-balance` takes "this method measures line length in stressed syllables ... not balanced", "syllable counts are the wrong measure", "the syllable count misleads" and "doesn't measure balance in syllables"; `family-distance-label` takes "medium-distance"; `finder-question-lists` takes "What is this loneliness like?" as the first list; and `no-single-winner` no longer flags a "How I'd choose:" guide. Each has pass samples from the runs and new fail samples.

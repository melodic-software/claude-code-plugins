---
bump: patch
---

### Fixed

- `video-digest` ASR transcripts now get the same proper-noun repair captions do: the repair lexicon is built from the title, description and harvested links for every transcript strategy, and the repair pass runs over ASR cues, so `repairedTermCount` counts their repairs.

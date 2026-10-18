---
bump: patch
---

### Fixed

- `video-digest` ASR transcripts now get the same vocabulary help captions do: the repair lexicon is built from the title, description and harvested links for every transcript strategy, passed to Whisper as the initial prompt, and the proper-noun repair pass runs over ASR cues, so `repairedTermCount` counts their repairs.

---
bump: minor
---

### Added

- video-digest: `watch/relayout-slice.js` copies a slice into the knowledge-corpus layout (`transcript/`, `metadata/`, `frames/all/`, `frames/key/`, `media/`, `analysis/`, provenance `README.md`), rewrites the slice paths its markdown names through a path map (a pipeline file the layout does not keep becomes plain text saying so), and exits 1 listing every slice-internal path that still does not resolve. It runs on a closed slice, or before `close` on one whose outcome checks pass so the temp media is still there, and refuses a slice whose temp media is gone unless `--no-media`, which takes nothing from the temp session. It builds the layout in a staging directory and moves it into place only when the link check passes; an existing target needs `--replace` ([#6902](https://github.com/melodic-software/claude-code-plugins/issues/6902)).

### Fixed

- video-digest: an auto-caption transcript paragraph no longer repeats the previous paragraph's closing words that a rolling caption carried over: 3 to 12 words compared case- and punctuation-insensitively, or 2 when the opening cue carries them from the cue before it, so a phrase the speaker genuinely repeats stays ([#6992](https://github.com/melodic-software/claude-code-plugins/issues/6992)).

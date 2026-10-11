---
bump: minor
---

### Added

- video-digest: `watch/relayout-slice.js` copies a slice into the knowledge-corpus layout (`transcript/`, `metadata/`, `frames/all/`, `frames/key/`, `media/`, `analysis/`, provenance `README.md`), rewrites the slice paths its markdown names through a path map (a pipeline file the layout does not keep becomes plain text saying so), and exits 1 listing every slice-internal path that still does not resolve. It runs on a closed slice, or before `close` on one whose outcome checks pass so the temp media is still there, and refuses a slice whose temp media is gone unless `--no-media` ([#6902](https://github.com/melodic-software/claude-code-plugins/issues/6902)).

### Fixed

- video-digest: an auto-caption transcript paragraph no longer repeats the previous paragraph's closing words (2 to 12 words, compared case- and punctuation-insensitively) that a rolling caption carried over ([#6992](https://github.com/melodic-software/claude-code-plugins/issues/6992)).

---
bump: minor
---

### Added

- video-digest: `watch/relayout-slice.js` copies a finished slice into the knowledge-corpus layout (`transcript/`, `metadata/`, `frames/all/`, `frames/key/`, `media/`, `analysis/`, provenance `README.md`). It finds the links, images, definitions and backticked paths in each markdown file with `mdast-util-from-markdown`, rewrites each one that names a copied slice path for the file's new location (a slice file the layout does not keep becomes plain text saying so), and exits 1 listing every slice-internal path that still does not resolve. It runs on a closed slice, or before `close` on one whose outcome checks pass, refuses a slice whose temp media is gone unless `--no-media`, builds the layout in a staging directory and moves it into place only when the link check passes; an existing target needs `--replace`. `context/output-contract.md` points at it in place of re-laying out by hand and lists what it cannot rewrite ([#6902](https://github.com/melodic-software/claude-code-plugins/issues/6902)).

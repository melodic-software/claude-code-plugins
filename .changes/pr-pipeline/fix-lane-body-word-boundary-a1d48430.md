---
bump: patch
---

### Fixed

- The issue lane's PR body and comments no longer cut a word in half. A summary longer than 3000 characters, or a change, check, not-done or remaining item longer than 300, is now cut at its last whitespace inside the cap and ends with `…`; one token longer than the cap is still cut at the cap, never inside a surrogate pair. Before this, each item was sliced at exactly 300 characters, which left #12396's body ending three lines mid-word.

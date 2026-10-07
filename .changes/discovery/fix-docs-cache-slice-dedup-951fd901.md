---
bump: patch
---

### Fixed

- **`scripts/docs-cache.sh slice` prints each line once, in page order
  ([#6501](https://github.com/melodic-software/claude-code-plugins/issues/6501)).** A slice that
  named a parent section and its child printed the child twice, because the parent's range already
  holds it; one measured request for 59193 unique bytes printed 75892. Overlapping and repeated ids
  now print their lines once, in the order they appear on the page.

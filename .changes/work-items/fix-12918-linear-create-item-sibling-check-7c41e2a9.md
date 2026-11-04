---
bump: patch
---

### Fixed

- `create-item --parent` in the linear seed adapter no longer files a second child with a title the parent already has ([#12918](https://github.com/melodic-software/claude-code-plugins/issues/12918)): when a child with the same trimmed title is open, or was completed or canceled within 24 hours, it creates nothing, exits `0` and prints that child, as the GitHub and local-markdown adapters already do.

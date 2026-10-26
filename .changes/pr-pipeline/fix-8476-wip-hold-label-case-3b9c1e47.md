---
bump: patch
---

### Fixed

- The issue lane's WIP cap counts a lane pull request as held when it carries `needs-human` or `do-not-merge` in any case (for example `Needs-Human`), as pr-merge's `enable-auto-merge.mjs` (`holdReason`) matches them, so a hold label with other casing no longer leaves the pull request in the countable total ([#8476](https://github.com/melodic-software/claude-code-plugins/issues/8476)). A label with a missing or non-string name is no hold, and the `Hold: a human merges this` body line still matches exactly.

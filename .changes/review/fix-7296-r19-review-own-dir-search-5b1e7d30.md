---
bump: patch
---

### Fixed

- `/review:security-review` and the `review:lane-verifier` agent search only the repository under review, never the installed review plugin copy (a review plugin source tree inside the repository under review is part of it), and the inert-key rule names the changed plugin's files as the ones searched ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).

---
bump: patch
---

### Fixed

- The pr-merge lane holds a pull request when a person's comment says "do not merge" or carries blocking language, checked before the enqueue with the autopilot tier's human-veto scan ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane), [#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).

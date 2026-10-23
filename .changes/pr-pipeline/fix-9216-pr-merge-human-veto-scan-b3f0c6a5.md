---
bump: patch
---

### Fixed

- The pr-merge lane holds a pull request before it enqueues when a person's newest comment on it says "do not merge". A later comment from that person lifts the hold ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane), [#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).

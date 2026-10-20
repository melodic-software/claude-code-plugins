---
bump: patch
---

### Fixed

- pr-merge holds a stale-input pull request at its old head when the `update-branch` call gets no answer (a timeout, no HTTP status, or a server error), since the update may have landed; only a 4xx refusal enqueues as before. `merge.check-inputs` reads only a clone that is neither shallow nor partial ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

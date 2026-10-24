---
bump: patch
---

### Changed

- A review-dependency `merge` verdict on a Dependabot pull request that changes a workflow or action file no longer waits for a person, and the `dependency-workflow-held` escalation reason is retired. The verdict job instead posts the merge marker only when that change is a full-SHA pin swap: every changed line in those files a `uses:` line that keeps its indent and action path, with both refs full 40-hex SHAs, so only the SHA and the trailing comment differ. Anything else (a tag ref, a path change, a new step, a `run:` change, an added or removed line, an added or deleted file) escalates the new `dependency-workflow-unpinned`. A lane fix still never lands under `.github/`.

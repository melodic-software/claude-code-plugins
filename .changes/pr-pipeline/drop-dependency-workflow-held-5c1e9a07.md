---
bump: patch
---

### Changed

- A review-dependency `merge` verdict on a Dependabot pull request that changes a workflow or action file now posts the merge marker like any other update, and the `dependency-workflow-held` escalation reason is retired. A security finding from the review lanes still stops the merge, and a lane fix still never lands under `.github/`.

---
bump: patch
---

### Fixed

- babysit-prs: the merge-risk cost check reads a `uses: $/...` self-repository call as a local workflow or action call, as it reads `uses: ./...`, so a timeout raised on a workflow whose local calls all use `$/` is still compared at its key path.

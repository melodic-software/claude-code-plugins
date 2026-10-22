---
bump: minor
---

### Changed

- resolve-config accepts `merge-base`, `review-threads` and `dependency-review` on a `read` skill
  that hands its change on as a patch (`applied-by.patch`), as the Activities section already
  describes, so those activities can move to the read runner. Without `applied-by.patch` the
  shape is still refused
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

---
bump: patch
---

### Changed

- `babysit-prs` merge gate: the post-merge floor reads the pipeline config's history from a local clone holding the base commit (the script's own checkout, else the working directory's) with `git log` and `git cat-file`, instead of two contents-API reads per config commit. A shallow clone, or one without the base commit, falls back to the API as before. The git path has no 100-commit limit; the API fallback keeps it. The pr-merge lane checks out main with full history.

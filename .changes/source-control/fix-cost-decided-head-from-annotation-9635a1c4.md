---
bump: patch
---

### Fixed

- `cost_decision` takes a cost decision's decided head from the review lanes' check-run annotations, never from a `github-actions[bot]` hold comment, which any workflow on `GITHUB_TOKEN` can post. The decided head is the `sha=` of the newest `claude-lane-hold ... criteria=` notice with `cost` that a review lane's status job (`pr-review-hosted.yml`, `pr-review-security-hosted.yml`) recorded before the decision, counted only where it names its own run's head. Every run on the head branch started before the decision must be on a head that changes neither review-lane workflow and lists fewer than 300 files, or nothing carries; two heads noticed at the newest time carry nothing. The runs, jobs, annotations and those compares are read with `BABYSIT_VERIFY_GH_TOKEN` when it is set. The edit and deletion checks on the hold comment are gone with the comment read.

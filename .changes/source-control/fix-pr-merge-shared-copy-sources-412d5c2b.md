---
bump: patch
---

### Fixed

- pr-merge refuses to enqueue a pull request carrying a shared-library canonical (the canonical or a copy it touches, or a copy it registers) that main changed since its merge base, and escalates it to a person with the human-gated role label and one comment naming the canonicals and the fix: merge main, run `scripts/sync-shared-copies.sh`, and push. An update from main alone left the pull request's copies stale, and the queue's copy-drift check failed ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

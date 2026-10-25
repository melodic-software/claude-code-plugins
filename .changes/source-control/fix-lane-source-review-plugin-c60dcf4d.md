---
bump: patch
---

### Fixed

- Babysit review evidence no longer unbinds both review lanes (`lane-source-changed`) for a pull request that changes `plugins/review/`. The reusable `pr-review-cli.yml` stages the review plugin from claude-code-plugins' default-branch tip, never the head, so a pull request's copy feeds no review. `scripts/ci-review-plugin-source.test.sh` fails if either review caller stops calling that reusable pinned to a commit SHA or passes it a plugin path. Every other lane-source path still unbinds.

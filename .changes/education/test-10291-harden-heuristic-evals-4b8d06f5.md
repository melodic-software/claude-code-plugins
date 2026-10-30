---
bump: patch
---

### Fixed

- The `non-obvious-behavior-keying` eval case no longer asks the model to catch subtle behavior shifts. Its prompt calls the change mostly a refactor, and its scaffold puts a refactor-framed patch header and surface-only hunks (a version bump, a `JWT_SECRET` rename) ahead of the auth hunks. The `-behavior-present` variant keeps its stated heuristic on the same prompt and fixture. Before this change, the base model passed `not-surface-only` in 3 of 3 runs in both arms of the [#10235](https://github.com/melodic-software/claude-code-plugins/issues/10235) run, so the case could not discriminate. ([#10291](https://github.com/melodic-software/claude-code-plugins/issues/10291))

---
bump: patch
---

### Fixed

- The `already-built-disconnected-scan` eval case no longer asks the model to check for something already built. Its prompt asks what to work on next, and its scaffold adds an approved `docs/bulk-export-plan.md` claiming nothing exports orders today. The `-behavior-present` variant keeps its stated heuristic on the same prompt and fixture. Before this change, the base model ranked the disconnected export first in 3 of 3 runs in both arms of the [#10235](https://github.com/melodic-software/claude-code-plugins/issues/10235) run, so the case could not discriminate. ([#10291](https://github.com/melodic-software/claude-code-plugins/issues/10291))

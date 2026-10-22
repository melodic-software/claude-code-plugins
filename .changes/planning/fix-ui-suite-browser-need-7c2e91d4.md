---
bump: patch
---

### Fixed

- The shared-page UI suite (`shared/tests/ui.test.sh`) fails under `CI=true` when node, playwright-core or Chromium is missing, instead of printing SKIP and passing. Local runs still skip.
- The shared-page UI suite runs `ui_telemetry.js` alone after the parallel suites, since parallel load hides the dead tap its one-second check waits for.

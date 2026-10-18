---
bump: patch
---

### Fixed

- **The render tests fail under `ANIMATION_REQUIRE_DEPS=1` when Chromium is missing.** `test_render.py` skipped without node, playwright-core or Chromium whatever the flag said, so CI passed without running it. It now fails under the flag, and CI's animation legs install the locked playwright's headless Chromium.

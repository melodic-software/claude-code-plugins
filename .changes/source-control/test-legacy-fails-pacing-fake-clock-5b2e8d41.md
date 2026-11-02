---
bump: none
---

Tests only: the legacy-fails pacing test drives a fake clock and asserts each requested wait is exactly 2 s, so a slow runner no longer fails it; no shipped behavior changes.

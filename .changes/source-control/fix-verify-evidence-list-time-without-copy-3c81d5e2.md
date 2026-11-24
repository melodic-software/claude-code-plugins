---
bump: patch
---

### Fixed

- The pr-verify evidence reader no longer refuses every pass that records no `trusted_actors_blob` once the repository's `.github/standards/trusted-actors/` copy is gone. Such a pass is now `verify:spec-changed` only when it did not start after the newest standards commit touching the trusted-actor list, as the pr-verify resolver (`resolve-pr.mjs` `specChanged`) judges it, so the gate and the resolver agree and an already-judged pull request no longer sticks.

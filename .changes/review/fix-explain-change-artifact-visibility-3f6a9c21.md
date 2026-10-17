---
bump: patch
---

### Fixed

- `explain-change` artifact gate: it looks up the repository's visibility itself (`gh api`, with the logged-in host check `publish-hosted.mjs` uses), so both media gate on one verified value. `digest-policy.mjs --publish-gate` now takes `--repo <[host/]owner/repo>` in place of `--facts`, and nothing in the facts file reaches the gate.

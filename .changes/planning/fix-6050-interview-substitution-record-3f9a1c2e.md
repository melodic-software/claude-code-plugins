---
bump: patch
---

### Fixed

- `/planning:interview`: the page lane's `user_config` substitution record no longer claims that an unset key with a `default` substitutes that default. The manifest reference does not say so, and our own probe (the `/harness-ops:plugins` record "`userConfig`: an unset key renders the literal placeholder") found the token stays literal. The record now treats a token the lane table shows literal as unset, whatever the key's saved state. It names each key's fallback (`surface` to `terminal`, emoji markers to off), points at that probe, and rechecks when a fresh-session probe records whether a saved boolean substitutes (`skills/interview/context/lane-page.md`).

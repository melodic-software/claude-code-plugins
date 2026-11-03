---
bump: patch
---

### Changed

- The dlss5 eval cases' Bash graders build their command pattern from the evals plugin's shared matchers, with no change to any pattern. The reply graders that judge a refusal or a reading (`force-not-a-way`, `proxy-not-a-way`, `refuses-anticheat-tamper`, `typed-name-after-review`, `no-pretyped-name-ack`, `user-moves`, `not-corrupted`, `verify-not-needed`, `reshade-kept`, `not-proof-of-none`) are `llm` graders now, each with at least eight near-miss fail samples.

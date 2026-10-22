---
bump: patch
---

### Fixed

- pr-verify's verdict upload checks the summary and notes against every shared credential pattern (`findSecret` in `lib/publish-gate.mjs`: GitHub, AWS, private keys and the rest), not only Anthropic key shapes, and the error names the matched kind.

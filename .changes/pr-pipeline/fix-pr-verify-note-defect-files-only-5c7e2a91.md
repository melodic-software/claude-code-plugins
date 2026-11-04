---
bump: patch
---

### Fixed

- A pr-verify `fail` now puts in `notes` only the lines that need a change, each saying what to change; a remark that asks for no change (a justified choice, a criterion met, coverage confirmed) goes in `summary`. Each note becomes a review thread that must be resolved before merge, so a remark there opened a thread nobody had to act on. The verifier prompt, the spec verifier prompt and the chunk note say the same; `pass-notes` and `pass` keep their rule.

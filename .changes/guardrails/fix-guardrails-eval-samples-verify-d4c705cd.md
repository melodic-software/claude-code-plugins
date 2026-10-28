---
bump: patch
---

### Fixed

- The `reference-verify` pre-push entry no longer verifies files under an `evals/` suite's `samples/` folder. Samples are recorded model output, so a CLI flag, skill reference or path inside one is data, and editing it would corrupt the eval. Prompts, graders and other eval files are still verified.

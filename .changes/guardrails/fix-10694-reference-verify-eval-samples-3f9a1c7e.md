---
bump: patch
---

### Fixed

- `reference-verify` pre-push entry: files in a `samples/` folder below an `evals/` folder, at the repository root or nested, are no longer handed to `cli-flag-verify`, `skill-reference-verify` and `stale-path-verify`. Those files are recorded model output, so a flag, skill reference or path in them is data, and editing them to pass would corrupt the eval. An eval suite's prompts, graders and fixtures, and a `samples/` folder outside `evals/`, are still checked.

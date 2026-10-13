---
bump: patch
---

### Fixed

- The rules index, the glob gate and the wiring gate now skip any `tests/fixtures/` tree the way they already skipped `evals/fixtures/`, so a unit-test fixture's `AGENTS.md`, `CLAUDE.md` or rule file no longer shows up as one of this repository's on-demand conventions or makes `check` report drift.

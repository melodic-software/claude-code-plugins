---
bump: minor
---

### Added

- **`/verification:confirm` records one row per acceptance criterion with its verdict.** The record now takes a `--row` per criterion, complete ones included: the criterion, the files that meet it, the test or check that proves it, and the result. A fix's first row is the reported symptom with its reproduction test failing on the base and passing on the head; a refactor's is "behavior preserved: same tests pass". `confirm-verdict.sh show` prints the rows.

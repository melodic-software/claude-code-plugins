---
bump: minor
---

### Added

- **Copy count and clone trend in `find`.** When `/code-metrics:audit-duplication` is available, `find` runs it with `--json --keep --all` and reads each clone class's copy count and the trend's new and grown classes, never an earlier report; copy count ranks spread in the code dimension. That run keeps one report in code-metrics' data directory as the next trend baseline, and the skill body and README now name both writes. A growing class becomes a candidate whose next step is a lint proposal: `find` writes it to a review-findings file under `<memory_dir>/improvement/<branch-slug>/` with the memory-tier write discipline, names the file in the candidate row, and offers `/review:audit-enforceability` when that skill is available. No CI ceiling is proposed on a total clone count. Without code-metrics the run records a `gap:` line.

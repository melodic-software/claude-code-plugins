# 2.5 Record expected CI workflows

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

Classify changed files → predict expected workflows by reading the repo's own `.github/workflows/` triggers (path filters, `on:` events). Typical shape:

| File patterns | Expected workflow (example) |
|---------------|-------------------|
| Language sources (`*.cs`, `*.py`, `*.ts`, …) | that ecosystem's CI workflow |
| Shell scripts | shell lint workflow |
| Any PR | always-on workflows (AI review, CI gateway) |

Record the expected set for comparison in Phase 3.

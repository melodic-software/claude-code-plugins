---
bump: patch
---

### Fixed

- The `audit-over-compression-boundary` eval case loads again. Its `fixture-unchanged` grader matched the table separator rows with a literal `---`, which `claude plugin eval` read as the end of the grader's frontmatter, so the case produced no runs. The pattern now writes them as `-{3}`.

---
bump: patch
---

### Fixed

- `/evals:validate` now fails a grader or `prompt.md` whose frontmatter holds `---` on a line other than its two delimiter lines, and names that line. `claude plugin eval` cannot load such a file and runs nothing for its case; the validator used to pass it with exit 0 (#12202).

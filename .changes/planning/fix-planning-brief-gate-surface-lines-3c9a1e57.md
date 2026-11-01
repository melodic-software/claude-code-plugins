---
bump: patch
---

### Fixed

- The interview's Step 4 Brief gate command now passes `--surface '<data_dir>'` on a page-surface run, so it runs the Intent and Decisions checks. SKILL.md, `context/loop.md` and the checklist template name the flag.
- With `--surface`, `check-open-questions.sh --procedure --brief` now fails a Brief that lost a line the page export writes under its TLDR or Acceptance criteria.
- It also fails a Brief whose Decisions repeat an export line or hold a `Q<N>` line the export does not write, such as a decision put back in an earlier form or contradicted by a second line.

---
bump: patch
---

### Fixed

- **The `--brief` gate fails a page-export Brief that lost its Intent, Decisions or the user's own words** ([#11029](https://github.com/melodic-software/claude-code-plugins/issues/11029)). `scripts/check-open-questions.sh --brief --procedure` used to pass a Brief with `### Intent`, `### Decisions` or every Ask and own-answer line removed. Under `--procedure`, a Brief with a `- Restatement:` stamp now needs `### Intent`. A new `--surface <data_dir>` option exports the Brief from the interview page again and fails (`procedure=fail`) when the Brief lacks a section that export writes, or a line of its Intent. The page lane's wrap-up runs the gate with it.

---
bump: minor
---

### Changed

- **Exit codes in a script header pass the comment lint.** Under the `necessary` posture, the comment lines that open a file may carry an `Exit`, `Exit codes` or `Exits` heading and its numbered entries without a link. An entry's continuation lines also pass when they are indented deeper than its number. The rest of the header, and the same text after the first line of code, still fail. `/code-tidying:remove-comments` keeps the same exit-code list under `necessary`: the shipped keep list names it, so the fixer the lint points to no longer deletes what the lint accepts ([#17647](https://github.com/melodic-software/claude-code-plugins/issues/17647)).

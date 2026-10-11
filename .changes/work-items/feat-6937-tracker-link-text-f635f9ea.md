---
bump: minor
---

### Added

- **The tracker adapter owns the text that links a change to its item and the branch item-ID grammar.** A new offline `change-link` verb, implemented by every bundled adapter (github, gitea, jira, linear, local-markdown), returns the closing line (`Closes #42`, `Closes ENG-123`, or `null` where a merge closes nothing, as on Jira), the non-closing line, and the token a branch name carries; each manifest declares its branch grammar as `change_link.branch_pattern`. `/work-items:track link` exposes it to other plugins, and `track start`, `track done` and `work` now read it instead of writing GitHub's `Closes #N` and numeric branch names.

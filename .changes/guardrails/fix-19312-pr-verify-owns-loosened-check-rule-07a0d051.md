---
bump: minor
---

### Removed

- **`block-body-format-violation` no longer judges a `## Loosened checks` section.** It reads no
  linked issue and refuses no body for a loosened check, so a pull request with
  `No related issue: <reason>` and a reasoned section opens. Review and pr-verify judge the
  section by the review plugin's loosened-check rule. The hook's section, opener and issue-format
  checks are unchanged ([#19312](https://github.com/melodic-software/claude-code-plugins/issues/19312)).

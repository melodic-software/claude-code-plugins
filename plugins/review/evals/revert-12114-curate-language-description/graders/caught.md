---
type: llm
---

The answer is a code review of PR #12114, which trims the `description` of `plugins/domain-driven-design/skills/curate-language/SKILL.md` (587 to 506 characters) claiming "measured no-loss" from trigger passes where every score is at the ceiling (24/24 and 27/27) with only this plugin loaded. PR #12247 reverted it after a negative control showed a generic one-line description scored identically (51/51), meaning the cut was never actually measured.

PASS if a finding in the review (blocking or advisory) flags that the PR's "measured no-loss" evidence cannot prove the description cut is safe because the trigger suite is saturated at ceiling (24/24, 27/27), lacks a negative or detection control proving it would catch a degraded description, or tests only this plugin in isolation without rival skills so trigger regressions go undetected. Citing a specific file or line number is optional; findings on other grounds do not disqualify it.

FAIL if the review answers with no findings (such as "Findings: none" or a clean approval), reports only unrelated wording, punctuation, or YAML style nits on `SKILL.md` without questioning the unmeasured/ceiling-saturated no-loss evidence, or holds no review.

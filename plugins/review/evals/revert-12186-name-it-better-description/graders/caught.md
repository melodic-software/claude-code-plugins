---
type: llm
---

The answer is a code review of PR #12186, which shortens the `description` of `plugins/naming/skills/name-it-better/SKILL.md` (650 to 624 characters) claiming "measured no-loss" on held-out trigger probes and four routing cases without a negative or detection control. PR #12235 reverted it after a negative control showed `description: "Helps with naming."` scored 0.983 vs 0.967 on routing and 24/24 on trigger probes, proving the eval could not detect a description loss.

PASS if a finding in the review (blocking or advisory) flags that the PR's "no-loss" evidence for shortening `name-it-better`'s description is unproven because the eval lacks a negative or detection control proving it distinguishes the description from a generic/degraded one, is near ceiling, or runs without rival/competitor plugins loaded so routing regressions go undetected. Citing a specific file or line number is optional; findings on other grounds do not disqualify it.

FAIL if the review answers with no findings (such as "Findings: none" or a clean approval), reports only unrelated wording, punctuation, or YAML style nits on `SKILL.md` without flagging the unmeasured cut or missing negative/detection control, or holds no review.

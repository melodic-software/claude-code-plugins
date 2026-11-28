---
type: llm
---

The answer is a code review of PR #4960, which uses `Closes #3465` while adding only `docs/out-of-scope/provenance-repo-wide-sweep.md` to declare the repo-wide provenance sweep parked/out-of-scope instead of implementing any of the requested work. PR #5044 reverted it because merging a park ledger closed the active issue without doing the work.

PASS if a finding in the review (blocking or advisory) flags that the PR closes #3465 (or resolves/dismisses the issue) while only adding a park or out-of-scope document instead of implementing the requested work, or that parking/closing #3465 without completing it requires owner approval rather than a `Closes #3465` park ledger. Citing a specific file or line number is optional; findings on other grounds do not disqualify it.

FAIL if the review answers with no findings (such as "Findings: none" or a clean approval), reports only unrelated markdown formatting, link, wording, or metadata nits without flagging the unimplemented-work `Closes #3465` park ledger, or holds no review.

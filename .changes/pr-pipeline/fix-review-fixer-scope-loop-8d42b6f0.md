---
bump: minor
---

### Changed

- address-feedback's select job reads the closing issues' spec text when a kept thread is an unanswered `claude-review` advisory, and marks that thread `may_follow_up`; the reply job records the advisory as one bullet under `## Follow-ups` in the pull request body (the `Pre-existing (advisory):` marker the paused-filing sweep files from, its first line and a link to the thread, never twice), posts a `follow-up` reply saying so, and resolves the thread, so the fixer no longer adds a change the issue's scope forbids and the review lane then blocks
- the merge lane names an address-feedback `feedback-stood-open` stop in its refusal: the pull request's owning session settles the thread that stood, by fixing it or answering it with evidence, instead of the text saying the next lane run clears it

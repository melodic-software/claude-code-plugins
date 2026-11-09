---
bump: minor
---

### Changed

- address-feedback's select job reads the closing issues' spec text when a kept thread is an unanswered `claude-review` advisory, and marks that thread `may_follow_up`; the reply job posts a `follow-up` reply with a fixed line that the advisory belongs under `## Follow-ups` and resolves the thread, so the fixer no longer adds a change the issue's scope forbids and the review lane then blocks
- the merge lane names an address-feedback `feedback-stood-open` stop in its refusal: the pull request's owning session settles the thread that stood, by fixing it or answering it with evidence, instead of the text saying the next lane run clears it

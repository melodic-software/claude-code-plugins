---
bump: patch
---

### Fixed

- The adjudicator of a disputed review finding now reads the whole review comment and the files and lines it cites, beside the locations the fixing lane cited, instead of only the comment's first paragraph and the lane's locations (`.github/scripts/pr-unblock/adjudicate-feedback.mjs`).
- A disputed code-review finding carrying `severity: CRITICAL`, and a disputed pr-verify verifier note, go to a person again instead of to the adjudicator: resolving a verifier note's thread left its FAIL holding the merge with nothing to say so.
- pr-unblock's `adjudicate-feedback` job runs only when the answering leg's replies hold an `INCORRECT` reply; a round with none no longer checks out, sets up and stages for nothing. Its contents reads are logged in the job's api-budget notice.
- The monitoring lane's rolling issues render each finding's summary inside a text fence, in the body and the change comment, so a mention, link or tag in run or job text no longer works.

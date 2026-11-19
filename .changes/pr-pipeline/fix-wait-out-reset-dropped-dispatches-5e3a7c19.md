---
bump: patch
---

### Fixed

- A pull request's Refine dispatch and intake's issue refinement no longer drop on a GitHub token budget stop whose reset is near. pr-unblock-dispatch's refine job waits out a rate-limit stop (up to 1200 s) and then sends the pr-refine dispatch, where before it ended red with nothing to send it again. check-kill-switch takes a new `wait-seconds` input: a budget stop whose reset is inside it waits for the reset and reads the budget once more. Only intake's refine-select sets it, so admission no longer refuses an issue whose refinement the start gate skipped.

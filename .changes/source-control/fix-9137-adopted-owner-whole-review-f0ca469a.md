---
bump: patch
---

### Fixed

- pr-merge requests a whole review of an adopted owner pull request (`Eligibility.adoption`) held only by findings a clean whole review would close, with the same bounds as a lane pull request: once per head, at most `MAX_TOGGLES`, one per run and the rate-limit share. `_whole_review_record` had skipped any pull request the agent identity did not open. Adoption no longer refuses `updated-fresh` while the lanes App's newest reasons comment records a request at the current head and no person has spoken since that record (`lane_toggled_at_head`), so the record, the toggle and the whole review it starts do not reset the idle clock. The head commit test, every hold and the draft refusal are unchanged.

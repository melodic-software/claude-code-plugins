---
bump: patch
---

### Fixed

- pr-unblock's `feedback-incomplete` escalation names each kept review thread with no recorded disposition, where it named none and the log gave only counts (#8257). `publish-feedback.mjs` logs each one's id and names at most 20, with their root comments and then how many more, in the round marker it posts; `report-escalation.sh` lists them with each root comment's URL from the newest lanes App round marker on the head it stops on. With no such marker it says so and points at the run's publish-feedback log. No reply is posted, as before.

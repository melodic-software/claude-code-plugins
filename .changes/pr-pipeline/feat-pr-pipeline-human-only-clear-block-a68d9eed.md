---
bump: minor
---

### Changed

- `pr-merge` now keeps a lanes-App `needs-human` label only when a person commented, reviewed, or
  left a review or commit comment since it went on. A comment or review by a bot account (an AI
  review, another lane) no longer blocks the clear. An App comment carrying any marker other than
  pr-unblock's escalation still keeps the label.

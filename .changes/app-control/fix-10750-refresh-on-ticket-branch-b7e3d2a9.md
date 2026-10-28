---
bump: patch
---

### Fixed

- `/app-control:map refresh` started on a ticket branch commits its doc-drift corrections on that branch and opens no upkeep pull request, so the ticket's pull request carries them and they merge, or are dropped, with the code they describe. Before, the corrections went to an upkeep pull request cut from the default branch, which could merge ahead of the ticket or without it. A pass started on the default branch keeps the upkeep branch and its one pull request. On a ticket branch, a pass due a conversion is blocked until it runs from the default branch, and a detached HEAD off the default branch's tip commits nothing.

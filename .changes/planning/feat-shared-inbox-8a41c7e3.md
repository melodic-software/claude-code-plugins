---
bump: minor
---

### Added

- Shared interview: an Inbox replaces the bell in the top bar. It lists your own requests to Claude, newest first, each with its question, what you asked, and its status (Waiting, Running, Answered, Shared, Declined or Failed with the reason), and opens the answer in that question's Claude section. Its badge counts what changed since you last opened each item; only opening an item marks it read, on every device. For the host it adds "Waiting on you": requests to run, results to share, problem reports, merge requests and join requests, each opening where it is handled. Every notification kind is still listed under Notifications in the Inbox. A toast "Claude answered your request on Q<N>" with Open appears when one of your requests is answered.

### Changed

- Shared interview: a request the host sends runs at once and its answer shows to everyone at once, with no Run or Share step. Guests' requests, including the host's own guest identity, still wait for Run and Share; a guest's Inbox reads "Answered, waiting for the host to share" until then.
- Shared interview: the session file moves to schemaVersion 4, which records what each person opened in the Inbox. An older file is upgraded on load with every existing request marked read.

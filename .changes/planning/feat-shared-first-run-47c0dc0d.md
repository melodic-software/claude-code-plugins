---
bump: minor
---

### Added

- Shared interview sessions: a per-person "Go to the next question after I answer" switch, off by default, moves on 2 s after a single pick, confirm or scale value with the comment box empty, with Stay to cancel; never after pick-many, rank or a written answer.
- Shared interview sessions: "Your reports" in More and Help lists a person's problem reports with Sent, Seen by the host or Fixed, and takes an added line or screenshot while a report is not fixed (`POST /api/report/add`).
- Shared interview sessions: the first view's welcome card opens with "Enter your name to join, then answer this round's questions.", shows once per person per device, has a visible Skip that also skips the tour, and comes back with "Show the tour again" in the person's settings.

### Changed

- Shared interview sessions: a guest's Ask Claude has one box with no Ask, Research or Explore picker; Claude works out how to answer, and a "Use the web" chip sends the request as research. The owner keeps the picker.

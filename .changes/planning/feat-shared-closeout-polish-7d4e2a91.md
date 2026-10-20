---
bump: minor
---

### Added

- Shared interview page: the host sets which pop-ups guests start with under Guests start with in the Inbox's Notifications tab (the `guestPopups` setting); a guest's own switches win once changed.
- Shared interview page: the Host view's people list shows how many of the open round's questions each guest still owes, and a Behind chip lists them.
- Shared interview page: on a return visit a guest sees the session goal in one line they can close for the rest of that visit.
- Shared interview page: in Facebook's, Instagram's or Messenger's in-app browser a guest gets a banner suggesting Safari or Chrome; Get your link opens the device panel with its Keep this private warning. It never blocks the page, and the owner never gets it.
- Shared interview page: About you in a guest's own card (how comfortable they are with tech, and a note), shown only on the owner's Host view.
- Shared interview page: after two minutes waiting for Claude or in "Claude is working", the round says for how long; while a round waits the owner reads that Claude may already be reading it.
- Shared interview page: when a filter or round pick hides questions, the rail says so ("Showing round 2 · 1 round hidden") with Show all.

### Changed

- Shared interview: the session file is no longer versioned. `migrate.py`, the `schemaVersion` key, the prototype import (`ensure-running --import`, `server.py --initial-state`) and the prototype pages' reload banner are gone; a `schemaVersion` 7 is dropped on load, and a file below 7 is refused with a message to start a new session or migrate under the previous build first. To go back to an earlier build, add `"schemaVersion": 7` to `state.json`. A page still reloads when the build changes.
- Interview skill, shared lane: `ack-round` goes in the same apply as the next `open-round` or `close-round`, and any question for the owner comes after it lands.

### Fixed

- Shared interview page: a question asked once per device (`answerScope: device`) now takes answers from the page, and a person who answered on another kind of device is asked for this one too. A touch device is a phone or a tablet by its screen's short side, so a phone turned to landscape stays a phone.

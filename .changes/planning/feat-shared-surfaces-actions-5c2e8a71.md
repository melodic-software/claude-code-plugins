---
bump: minor
---

### Added

- Shared interview page: a guest waiting for the host to let them in sees one centered card with the session title, "Why you're here" and the wait, and nothing else of the session until admitted; the server's waiting refusal carries the title and intro.
- Shared interview page: guests get their own Pop-ups switches in the Inbox's Notifications tab (Claude answered my request, a mention, a new round), all on until turned off.
- Shared interview page: the full-screen Inbox uses two columns from 1100 px (Needs you side by side; Pop-ups and the notification switches in a sticky column beside the messages), and below that keeps the messages first with Pop-ups and the switches behind one "Pop-ups and notifications" button; "Show in Host view" sits in each row's own actions.
- Shared interview page: the tour adds the Discussion, Ask Claude with @Claude, attaching a file and the Inbox for guests, and Share, Needs you (Run and Approve) and Send for the host.
- Shared interview page: a guest's desktop Help has Settings, which opens their own card.
- Shared interview page: the host's Pop-ups gain "Someone offers a file", off until switched on; on, a file a guest offers pops up for the host.

### Changed

- Shared interview page: every popover, panel and sheet opens through one surface model with one close x named for what it closes, one focus trap and one 720 px breakpoint, so the Ask Claude panel is a side drawer down to phone width.
- Shared interview page: Help and More draw one menu model; chat messages and Discussion comments share one message menu (Reply, React, Propose as question, Ask Claude about this, Copy, and Edit, Delete or Hide where allowed), opened by ⋯ or a long press.
- Shared interview page: person, proposal, request and result actions each come from one builder, with the same words and toasts in the person card, Host view, person view, Settings, Proposed, the queue, Later, the thread, Ask Claude and the Inbox; every Copy uses one copy path.
- Shared interview page: sending a round with open questions, and declining a request, join or merge, ask first through the one confirm dialog.
- Shared interview page: a toast is the result of the person's own action or a pop-up they switched on, and never a kind they muted; everything else from others waits in the Inbox.

### Fixed

- Shared interview page: the question's Ask Claude button no longer claims a menu it does not open.
- Shared interview page: a prototype page reads as read-only for a guest once the session ends or they are removed.
- Shared interview page: an answer's device badge names the browser in words, from the one device and browser source.

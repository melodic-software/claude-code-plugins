---
bump: minor
---

### Added

- Shared session: every place people write (the answer box, Ask Claude, chat, the Discussion and Propose) has an
  Attach button while Uploads is on, and a picture pasted into any of them is shrunk in the browser, offered to the
  host and shown as a thumbnail chip that reads "Waiting for the host" until it is accepted. Chat messages, requests,
  suggestions, proposals and comments carry accepted uploads, and a request's files reach Claude in `request-run`.
- Shared session: every picked or pasted picture is redrawn in the browser (at most 1600 px and 512 KB, no EXIF or
  GPS) before it is offered. Once received and, for a guest's, approved by the host (Approve picture in the Host
  queue), it shows as a tile, which opens the viewer, to everyone who can see what carries it, read back through
  `GET /api/upload/image` as a data: URL; a Just me request's, a proposal's or a hidden comment's files never reach
  another guest. The host or the uploader can remove a received file from everything that carries it.

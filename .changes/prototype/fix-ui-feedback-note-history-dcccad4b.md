---
bump: minor
---

### Added

- **After a reload, the notes host lists the run's notes and drafts again.** Sent notes come from a new `GET /api/notes` bridge route. It needs the page token and serves only the running bridge's own data dir. Drafts are kept in the tab's sessionStorage under the run's token and are never sent to the server. Notes are listed oldest first, numbered as their markers are. Hovering a row draws its note's box on the mockup. Clicking a row, or its marker, restores the note's variant, screen state and content set, scrolls to the note, and keeps the box drawn until you click elsewhere. A marker takes a click only on its own box, and only outside a pick mode ([#17801](https://github.com/melodic-software/claude-code-plugins/issues/17801)).

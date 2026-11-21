---
bump: minor
---

### Added

- **The notes host lists the run's sent notes again after a reload.** They come back oldest first, numbered as their markers are, from a new `GET /api/notes` bridge route that needs the page token and serves only the running bridge's own data dir. Hovering a row draws its note's box on the mockup. Clicking a row, or its marker, restores the note's variant, screen state and content set, scrolls to it, and keeps the box drawn until a click elsewhere. A marker takes a click only on its own box and only outside a pick mode. Drafts still live only on the page, so a reload loses them ([#17801](https://github.com/melodic-software/claude-code-plugins/issues/17801)).

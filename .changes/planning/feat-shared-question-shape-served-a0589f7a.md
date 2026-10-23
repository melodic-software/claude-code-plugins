---
bump: minor
---

### Changed

- The 1:1 interview page's answer note and Notes box use the shared page's composer: Ctrl or Cmd + Enter sends from the box, Escape leaves it, the key hint reads the composer's way ("Ctrl + Enter to save", Cmd on a Mac), a counter shows from 15,000 of a 20,000-character limit, and a box grows with its text up to 40% of its pane instead of 40% of the window. Single-key shortcuts and Ctrl or Cmd + Shift + Enter (Ask Claude) stay with the page.
- On a phone the 1:1 page is pinned to the visual viewport, as the shared page is: an on-screen keyboard shrinks the page instead of covering the note being typed, and the page scrolls inside itself rather than the document.
- Both interview pages load one shared file, `question-shape.js` with `question-shape.css`, which both servers serve: the composer kit, the visual-viewport fit, and the id of a person's own "Something else" option.

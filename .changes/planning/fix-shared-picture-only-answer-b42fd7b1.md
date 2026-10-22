---
bump: patch
---

### Fixed

- A picture sent with no typed text on the shared interview page is now saved as an answer. Before, the page said
  "Your answer is saved." while the server dropped the picture and cleared any earlier answer. Empty text with no
  picture still clears. The digest lists an answer's attached files, so Claude sees an answer made of pictures alone.

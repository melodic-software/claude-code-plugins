---
bump: patch
---

### Fixed

- The interview page's Finish no longer warns that you have not answered Claude in Notes just because Claude's reply was the last Notes entry. It warns only while a Claude note sent with `needsAnswer` has no answer. Each such note stays pinned in Loose ends until a note from you answers it, and each note you send answers the oldest one still open. A second `needsAnswer` note posted in the same apply is now pinned too, and one reply no longer clears both. The Brief's `asked in Notes, not answered` lines follow the same rule ([#11585](https://github.com/melodic-software/claude-code-plugins/issues/11585)).

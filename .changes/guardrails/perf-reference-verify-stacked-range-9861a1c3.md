---
bump: patch
---

### Changed

- reference-verify judges a stacked branch only on what it adds to the pushed branch below it

  The pre-push reference-verify entry now moves each range's base up to the nearest of the remote's tracking refs between that base and the tip. A new branch stacked on a pushed branch no longer re-verifies every file the branches below it changed, so each push in a stack of branches verifies only its own files. The README row states that those tracking refs are trusted as verified, another author's included. The README's reference-verify row also documents the ssh `ServerAliveInterval` setting. It keeps a long push's idle connection open; a dropped connection leaves a push that reports success but creates no ref.

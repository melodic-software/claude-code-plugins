---
bump: patch
---

### Fixed

- The babysit-prs verdict reader judges a pull request created more than `TOO_OLD_DAYS` ago like any other, so a fresh pass at its head allows it, and refuses `verify:too-old` only where no counted verdict is left at the head. `verify:too-old` is out of `VERIFY_FINAL` and `STANDING`, so `capped_close` no longer closes such a pull request ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).

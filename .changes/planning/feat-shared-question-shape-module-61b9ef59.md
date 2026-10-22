---
bump: minor
---

### Added

- On the 1:1 interview page, an alternative can carry a `tradeoff`, which the page shows under the alternative.

### Changed

- The 1:1 page's questions take `id`, `short`, `title`, `recommendation`, `dependsOn` and each alternative's text from the shared question shape schema, so `short` is now capped at 80 characters on the page as in the shared session; a file holding a longer `short` refuses every write until one `apply` revises each such label to fit.
- The shared session schema states the stored option bounds exactly: a choice holds 3 to 5 options, a multi 3 to 10 and a rank 4 to 7 (Claude's options plus the server's Something else and None of these), and Claude's open-round input takes 2 to 4, 2 to 8 and 3 to 6.

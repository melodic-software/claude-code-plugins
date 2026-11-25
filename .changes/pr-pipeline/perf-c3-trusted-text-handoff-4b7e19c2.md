---
bump: patch
---

### Changed

- pr-verify's resolver (`resolve-pr.mjs`) hands `select-trusted-text` the reads it already made of the pull request it judges: the pull request as `GET /commits/{sha}/pulls` listed it, and the first pages of its closing issue references and, where its spec query reads them, its title renames. `select-trusted-text` takes them through its new `reads-path` input instead of reading the pull request and those pages again, so each judgment spends one REST and, for a pull request whose body may be spec, one GraphQL call fewer. Both trust filters run unchanged on the handed-on text. The body is handed on with the edit stamp from the same spec answer, and is kept only when the edit query's stamp for the pull request still matches, so an edit between the two reads withholds it; this also closes the gap between the pull request read and the edit query that a full read had. A handed-on pull request at a head other than the new `head-sha` input fails the step. A missing or malformed hand-off fails the step with no context written, as a failed read does, and the step deletes the hand-off either way.

---
bump: patch
---

### Fixed

- pr-verify now judges a pull request again at the same head after a trusted person fixes its body. Before, a FAIL at a head (for example one for a missing "Remaining on #N" section) blocked every new judgment there, so a body fix was judged only after an update-branch pushed a new head. Now this pull request's own FAIL at the head, plain or named with its issues, gives way when, since its last such FAIL's run was created, a person on the trusted-actor list edited the body and every body edit and issue link change since was such a person's. The resolver then proceeds with the reason `body-edited`. The body edit itself starts the judgment: `pr-require-checks` already runs on `pull_request` `edited`, and pr-verify runs when it completes. A Bot's edit, a link change alone, or an edit history that cannot be read whole keeps the FAIL, and the judgment still reads the edit history in one GraphQL query.

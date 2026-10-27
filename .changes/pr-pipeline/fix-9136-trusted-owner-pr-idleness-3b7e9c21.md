---
bump: patch
---

### Fixed

- In the pr-merge lane, adoption's idle rule reads a person's pull request's newest activity, not its raw `updatedAt` (#9136): the pull request's opening, the head's arrival, and each comment, review, inline review comment, label change, title edit, review request, ready for review, reopen or force push whose actor id is on the trusted-actor list. Another account's comments no longer keep an owner pull request from going idle there, unless one is a hold: its changes-requested review, or a person's comment or review saying "do not merge" or opening a line with `Hold:`, still refuses; a trusted person's request to wait still refuses. fix-ci still reads the last update.

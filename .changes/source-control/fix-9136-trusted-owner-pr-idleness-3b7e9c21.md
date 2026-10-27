---
bump: patch
---

### Fixed

- The pr-merge lane's idle owner pull request adoption measures a person's pull request's idleness from trusted activity only (#9136): its opening, the head's arrival as GitHub Actions' check suites record it, and each comment, review, inline review comment, label change, title edit, review request, ready for review, reopen or force push by an account on the trusted-actor list, never the raw `updatedAt`, which any commenter moves. Another account commenting every hour no longer keeps the pull request from being adopted, unless the comment is a repository owner's, member's or collaborator's hold: their changes-requested review, or a person's comment or review saying "do not merge" or opening a line with `Hold:`, still refuses `not-adopted:updated-fresh` while fresh, as does a trusted account's fresh comment, such as a person's request to wait. The lanes App's own pin and reasons comments do not count. An unreadable timeline or check suite listing, a listed event whose actor id cannot be read, or a counted event's unreadable time is not idle.

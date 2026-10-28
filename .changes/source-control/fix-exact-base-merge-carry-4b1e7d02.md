---
bump: patch
---

### Fixed

- A trusted person's approval of an earlier head now carries a hold-path lift over a base merge in the two cases that sent every such pull request back to them. An approval GitHub dismissed as stale on the merge's push still counts, bound to its own commit and only through the carry: the issue timeline's `review_dismissed` event has no message, a Bot actor and a dismissal commit among those pushed since the approved head (`auto_dismissed`). A dismissal with a message, by a person, or by a person's push still revokes it. When the base changed a file the pull request also changes, so the net change differs, the approval carries when the merges brought exactly the base's changes: the compare from the approved head to the current head equals, file for file with the same status and patch, the compare between the two merge bases with the base's tip (`exact_base_carry`, `approval_carry`, `carried_lifters`). A merge that writes any change of its own or drops a base change, a list of 300 files or more, or a commit list not read whole carries nothing. The owner's cost-decision carry is unchanged.

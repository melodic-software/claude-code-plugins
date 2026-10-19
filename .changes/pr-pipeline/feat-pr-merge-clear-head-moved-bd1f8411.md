---
bump: minor
---

### Added

- `pr-merge` also takes off a `needs-human` label the lanes App set for one of its own escalations
  once the head has moved: when the newest App comment carrying each of
  `<!-- babysit-merge-verify-escalation -->` and `<!-- babysit-merge-risk -->` names, in its
  ``at head `<sha>` ``, a head other than the current one, it posts one comment naming
  `head-moved`, the old head and the new one, then removes the label so pr-merge judges the new head
  and escalates again if its refusal still holds. A head that does not parse as 40-hex, any other
  marker, a label a person added, or a comment by any account but the lanes App since the label
  keeps it.

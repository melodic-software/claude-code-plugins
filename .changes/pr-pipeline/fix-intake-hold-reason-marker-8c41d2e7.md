---
bump: patch
---

### Fixed

- Every intake hold for a person now names its owner reason. Apply-verdict's held verdict comment
  and admission's held refusal comment carry the `<!-- stop-reason lane=intake-triage reason=<code> -->`
  marker and a `Reason:` line, the code `security`, `cost` or `intent`, the strongest of the
  hold's causes. Before, intake holds carried no marker, so every one read as unmarked.
- An issue that mixes done-when items an unattended lane run cannot perform with items the lane
  can do no longer holds at `status: needs-decision`. It parks at `status: confirmed`, and
  refine.mjs splits the other items off from there, as it still does for an issue held at
  needs-decision before this change. A split is no question for a person.
- A listed human's `**Decision recorded.**` comment written after the lanes App's verdict comment
  now answers that comment's carried `intent` flag and an unrecorded earlier flag, so a re-triage
  after the decision no longer re-holds the issue for them. A carried `security` or `cost` flag
  still holds, as does any flag the new verdict raises.

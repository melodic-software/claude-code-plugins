---
bump: patch
---

### Fixed

- The babysit merge gate's cost decision (`cost_decision`) clears a cost hold only when the owner's `**Decision recorded.** Cost:` comment also links its row in the owner-decisions record (`https://github.com/melodic-software/architecture/blob/<commit or main>/docs/owner-decisions.md#L<line>`) and quotes the owner after `verbatim:` in double quotes, both outside HTML comments. The gate checks the shape only, so a cleared hold is auditable, not provable. The cost-review hold's message says what the comment must carry.

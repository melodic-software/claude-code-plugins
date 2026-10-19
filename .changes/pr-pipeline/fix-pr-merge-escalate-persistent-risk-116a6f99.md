---
bump: patch
---

### Changed

- A pr-merge `risk:MED` or `risk:HIGH` refusal that persists across two sweeps at the same head now gets the human-gated role label after its reasons comment, while `merge.report-only` is false, so the pull request leaves the lane WIP count. The README also records the finding-closure rule as the owner's answer to whether a clean incremental review or a newer whole review closes a finding.

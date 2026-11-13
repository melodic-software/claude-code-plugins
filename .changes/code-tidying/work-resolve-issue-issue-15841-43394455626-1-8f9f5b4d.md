---
bump: minor
---

### Changed

- `remove-comments` writes its reshape flags, open root-cause work and lint-rule proposals to a
  findings file in every remove mode, not only lint proposals in `report` mode, so
  `/review:fanout fix` can pick them up. The file now goes in
  `<memory_dir>/reviews/<branch-slug>/`, the directory the fix action scans, rather than
  `<memory_dir>/comment-pass/`. Each row starts with its rule id from the detector-findings
  crosswalk:
  `code-tidying/remove-comments/rule-open-root-cause` (IMPORTANT),
  `code-tidying/remove-comments/rule-reshape-flag` or
  `code-tidying/remove-comments/rule-lint-proposal` (both SUGGESTION). Its `Action` names the fix
  or move to make. The skill still never makes a behavior-changing fix itself.
- Open root-cause work now also lists a workaround comment the run keeps, so a workaround's
  unfixed cause is reported whatever happens to its comment. A `TODO(#issue)` marker is still not
  listed.

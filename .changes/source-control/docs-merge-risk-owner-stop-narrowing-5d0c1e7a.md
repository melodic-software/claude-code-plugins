---
bump: minor
---

### Changed

- A merge after AI review with a HIGH or CRITICAL merge-risk rating (`demote=true`) now stops for the owner only when a reason no owner decision covers is a token or secret leak risk, an account-compromise risk, or something that can bill the owner. Any other uncovered reason is named in one pull request comment and the merge proceeds. A reason that cannot be read still holds, and a missing rating still blocks the merge.

---
bump: minor
---

### Added

- babysit-prs: the unattended merge policy readers in `babysit_merge_policy.py`: pipeline config at the base SHA through the shared YAML reader (bash resolved by Git Bash rules on Windows), the effective rung, the kill switch, the human-set rung cap, the demotion record, the agent identity, pull-request eligibility and the in-flight rule. Each fails closed; `assess()` composes them and stays inert, and `resolve()` is unchanged.

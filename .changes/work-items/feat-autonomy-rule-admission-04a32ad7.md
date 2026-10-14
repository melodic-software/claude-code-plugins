---
bump: minor
---

### Added

- `scripts/rule-admit.sh` evaluates the owner's C1/C2 admission rules from the security binding for GitHub issues, with no model and no label writes, and reports admit or refuse per issue. The work-loop admission gate runs it as a second admission path for items without an admitted autonomous-eligible label; a rule-admitted C1 gets no push or PR, and a rule-admitted C2 PR carries the human-merge hold.

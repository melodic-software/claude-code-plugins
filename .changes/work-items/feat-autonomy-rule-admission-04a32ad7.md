---
bump: minor
---

### Added

- `scripts/rule-admit.sh` evaluates the owner's admission rules from the security binding for GitHub issues, with no model and no label writes, and reports admit or refuse per issue. Only C2 rules admit, and a rule-admitted C2 PR carries the human-merge hold; C1 rules refuse until a mechanical no-push exists. The script exits 4 unless the binding's `dispatch_posture` is `autonomous-enabled` and its decision table makes each rule's class autonomous-eligible for issues under every provenance. The work-loop admission gate runs it as a second admission path for items without an admitted autonomous-eligible label.

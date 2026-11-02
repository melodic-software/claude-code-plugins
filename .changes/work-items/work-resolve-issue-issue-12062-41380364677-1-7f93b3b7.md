---
bump: major
---

### Changed

- `/work-items:triage` no longer requires a work class for the autonomous-eligible role. A delegable, decision-defaulted or multi-surface stub outcome applies `agent-ready` with or without a `work-class:` label, and the five-label preflight before those outcomes is gone. The one pairing ban left: `work-class: untrusted-provenance` or `provenance: signal` is never paired with `agent-ready`.
- A triage lane that may not write `work-class:` labels now applies `agent-ready` to a delegable outcome instead of human-gating it with a proposed class.
- The triage `sweep` no longer skips a human-gated item for carrying `work-class: structural` or no `work-class:` label.
- `/work-items:attend-queue` flips an escalated item to `agent-ready` whatever its work class, and with none. Only `work-class: untrusted-provenance` or `provenance: signal` still blocks the plain flip.

### Removed

- Triage's "Lane barred from recording a class" branch.
- Attend-queue's "No recorded class: stamp, then flip" rule and the rule that `work-class: structural` is reclassified before the flip.

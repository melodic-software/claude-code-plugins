---
bump: patch
---

### Changed

- Upstream Claude Code behavior the audit skill, its references, the check skill, the README and the settings-write hook relied on is now read live through anchored pointer records (as of 2026-10-11, each with a recheck trigger) instead of restated. `/doctor` coverage now points at the skills page section that owns it, and the interactive-only tool names live only in `interactive-only-tools.json`.
- The audit's emitted `knownUncovered.notes` text for EndConversation changed: it now says the audit never prices a bare-name deny of that tool and points at the permissions page section that owns deny-rule behavior, instead of restating that behavior.

### Fixed

- The late-connector record cited the 2.1.260 changelog entry; that fix shipped in 2.1.261.

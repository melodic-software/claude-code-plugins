---
bump: patch
---

### Changed

- Agent-facing references now point at the exact live Claude Code docs section for upstream load limits, version floors, flag behavior and subagent loading instead of restating them, each with an as-of date and recheck trigger: `write-for-agents` surface table, `audit-progressive-disclosure` tier model and sources, `audit-derivability` spot-test rubric, `extract-ssot` propagation-lag anti-pattern and `batch` action, `rename-references` auto-memory location, `audit-encapsulation` worker cap and the `compare-labeler` turn cap.

### Fixed

- `write-for-agents` no longer calls user rules lower priority than project rules, and no longer says AGENTS.md loads only where no CLAUDE.md sits at or above the working directory; it points at the Project instructions setting that changes that.
- `audit-progressive-disclosure` no longer labels the skill-listing drop order a community detail; it points at the docs section that now covers it.
- `rename-references` resolves the configured auto-memory directory before sweeping or excluding memory files, instead of assuming the default path.

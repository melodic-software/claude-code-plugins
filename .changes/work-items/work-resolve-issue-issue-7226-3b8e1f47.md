---
bump: patch
---

### Removed

- work-loop: removed the manual C3 ratification gate check and its `skills/work-loop/AGENTS.md` (#7226). The check can only run on a GitHub tracker, because it needs comment authorship and label provenance that the local-markdown adapter does not provide. The work-loop `SKILL.md` no longer points at the check.

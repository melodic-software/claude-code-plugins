---
bump: patch
---

### Fixed

- **Residency, precedence and liveness rules point at the live docs sections instead of quoting them.** The cross-surface conflict criteria, the Phase A inventory, the `/doctor` handoff, the AGENTS.md liveness record and the audit checklist had copied upstream text that has since changed: subagents can now opt out of CLAUDE.md, user and project rules no longer have a stated winner, CLAUDE.md files have a size limit, another hook event's stdout reaches context, skill preloading is capped, skill-frontmatter hooks live for the rest of the session, Haiku 5.5 has its own default effort, `DISABLE_DOCTOR_COMMAND` is documented again, the built-in AGENTS.md plugin has a new settings id, and managed sources can merge. Each rule now states our decision and fetches the specific from an anchored pointer with an as-of date and a recheck trigger.

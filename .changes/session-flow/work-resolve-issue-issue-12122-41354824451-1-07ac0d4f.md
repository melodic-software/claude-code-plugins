---
bump: minor
---

### Added

- Retro session mode now looks for five environment findings and names a route for each: an existing check that is unwired or broken (reported before any new check is proposed), a recurring mistake with no guardrail, information the session could not reach, a no-op line in a steering file, and a missing navigation pointer after a long search. Steering-file findings are judged against `/docs-hygiene:write-for-agents`, and the efficiency assessment gains a tool-economy line. A new eval case covers the unwired check.

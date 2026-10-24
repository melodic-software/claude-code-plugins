---
bump: minor
---

### Changed

- This repository sets `merge.dependabot.majors: review`: a Dependabot major, unreadable or disagreeing update merges on the pr-unblock review's `verdict=merge`, as any tier `review` update does, instead of waiting for a person (owner direction 2026-10-24; ADR 0073 addendum).
- `dependency-classify.mjs` reads a security update's version jump from its verified commit subject when the metadata has no `update-type`, matching the pr-merge classifier.
- `clear-escalations.mjs` clears a pr-merge Dependabot-major escalation when the head moves, like pr-merge's other escalations.

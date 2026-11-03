---
bump: patch
---

### Changed

- move the handoff skill's WIP-commit mechanics and /export record out of its hub

  The /session-flow:handoff SKILL.md body drops from 36,785 to 34,609
  bytes (frontmatter stripped). The WIP commit's refusal checks, staging
  and record, and the /export verification record, move verbatim to
  reference files read on demand, listed in a new reference index. A new
  ho-wip-commit-on-pause eval case covers the moved WIP-commit text.

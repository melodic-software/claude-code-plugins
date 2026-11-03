---
bump: patch
---

### Changed

- `mp-sung-line-template` now accepts a hand-off to `/songwriting:co-write` through the Skill tool. `positional-template` and `routes-to-co-write` read the trace instead of the final reply, so the template and the route are graded on meter-prosody's own messages, and a Skill call to `songwriting:co-write` also passes both. Every branch matches only assistant lines, so the template in a `meter.md` Read result and the skill listing do not count. Their samples are synthetic trace lines with the near misses (a template only in a tool result, a thinking block or a user line, a Skill call to another skill, a Read of co-write's SKILL.md).
- The case's turn cap rises from 10 to 20, since hand-off runs reached the old cap.

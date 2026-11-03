---
bump: patch
---

### Changed

- `mp-sung-line-template` no longer lists `Skill` in `allowed_tools`. The slash prompt still loads meter-prosody. `Skill` stays offered, so a run can still hand off to co-write; `no-fitted-line` is what fails such a run.
- `positional-template` and `routes-to-co-write` read the trace instead of the final reply and match any assistant text block, co-write's included after a hand-off, so the template in a `meter.md` Read result and the skill listing do not count. Their samples are synthetic trace lines with the near misses (a template only in a tool result, a thinking block, a user line or a tool call's input; co-write named only in a tool input).
- The case's turn cap rises from 10 to 20.

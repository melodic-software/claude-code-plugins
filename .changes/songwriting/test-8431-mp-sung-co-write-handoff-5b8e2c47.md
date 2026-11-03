---
bump: patch
---

### Changed

- `mp-sung-line-template` no longer lists `Skill` in `allowed_tools`. The slash prompt still loads meter-prosody, and the graders read meter-prosody's own reply rather than co-write's output after a hand-off.
- `positional-template` and `routes-to-co-write` read the trace instead of the final reply and match only assistant text blocks, so the template in a `meter.md` Read result and the skill listing do not count. Their samples are synthetic trace lines with the near misses (a template only in a tool result, a thinking block, a user line or a tool call's input; co-write named only in a tool input).
- The case's turn cap rises from 10 to 20.

---
bump: minor
---

### Changed

- A proven vendor pair keeps recording Claude's review verdicts: `vendor-state record` keeps its newest `trials_prove` results and sends the pair back to trial when `trials_fail` of them are rejected. `/multi-agent:route vendors` records the verdict for proven pairs too, and `vendor-state send-back` also clears those results.

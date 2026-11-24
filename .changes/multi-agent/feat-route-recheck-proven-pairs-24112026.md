---
bump: minor
---

### Changed

- A proven vendor pair keeps recording Claude's review verdicts: `vendor-state record` keeps its newest `trials_prove` results and sends the pair back to trial when `trials_fail` of them are rejected. `/multi-agent:route vendors` records the verdict for proven pairs too, and `vendor-state send-back` also clears those results.
- A heavy-task trial (`--task-class heavy`) runs at the level the vendor's own effort guidance gives, passed as the new `vendor-decide --heavy-effort <vendor>=<level>`, else one step above the model's default effort; an everyday trial keeps the default. Heavy and everyday trials are separate pairs, each proven on its own.

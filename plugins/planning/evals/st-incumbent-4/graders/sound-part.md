---
type: llm
focus: last_message
---

The reply reviews a draft plan for an invoicing app that decides whether to replace the field
encryption library sealing customer data. One part of the draft is sound: Vaultline's 4 KB value
limit is far above the model's field caps (the longest field, email, is 254 characters). This
grader checks only that the reply leaves the size limit alone. The case's other graders score the
defects it finds.

PASS if no finding says a value can exceed the 4 KB limit. A reply passes when it approves the
limit, says no field comes near it, reports other defects (Vaultline's random output breaking the
email lookup, `Sealbox.rekey` existing since 5.0.0, or the reseal task failing on a re-run), or
flags nothing.

FAIL if any finding says the 4 KB limit is too small, that sealed values can exceed, overflow or
be truncated by it, that the value size claim is unverified or needs measuring, or that nothing
checks values stay under it. A finding that quotes the draft's approval of the limit and then
attacks it fails.

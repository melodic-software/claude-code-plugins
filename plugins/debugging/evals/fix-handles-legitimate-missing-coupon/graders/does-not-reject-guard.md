---
type: llm
focus: reply
---

PASS if the reply accepts the handling of a missing coupon code as the fix and does not treat the absent code as a bug to trace upstream.

FAIL if the reply rejects or downgrades the guard for a missing coupon as a symptom fix, or goes looking for why the coupon code is missing (for example, makes the form require a coupon, or traces where the code should have been set).

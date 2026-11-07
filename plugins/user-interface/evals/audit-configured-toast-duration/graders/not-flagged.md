---
type: llm
arm: both
---
Expectations: "The 400ms toast duration is not reported as a duration finding" and "The
answer refers to the configured role duration, not a fixed 300ms cap".

The team file `docs/conventions/user-interface.yaml` sets `animation.duration_ms.large` to 600,
and a toast is judged against `large`. PASS only if the report does not list the toast's 400ms
entrance as a duration finding (listing it as suppressed, with the configured role as the reason,
is fine) and the answer refers to the configured large role (600ms) rather than a fixed 300ms cap.
FAIL if the 400ms duration appears as a finding at any severity, or the answer judges it against a
300ms (or other fixed) limit.

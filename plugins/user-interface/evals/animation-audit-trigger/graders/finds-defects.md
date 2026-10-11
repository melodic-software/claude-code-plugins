---
type: llm
arm: both
---
The seeded src/notifications.css has six animation defects: an entrance from `scale(0)`, `ease-in`,
`transition: all`, a 700ms duration (over every role, `large` included), a `:hover` scale not gated to
precise pointers, and no reduced-motion handling.

PASS only if the report names at least five of the six, each tied to the file (a line number or
the rule it sits in), with some severity or priority ordering. FAIL if it names four or fewer, or
claims the file is fine.

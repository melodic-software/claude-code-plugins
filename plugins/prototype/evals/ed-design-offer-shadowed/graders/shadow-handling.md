---
type: llm
focus: last_message
arm: both
---
PASS only if the reply, before anything is built, (1) does not suggest that the user run /design
as a design-canvas alternative to this skill, and (2) tells the user that a local skill named
design in this session takes the /design name, so /design would not open the bundled design
canvas. FAIL if the reply suggests /design as a canvas alternative, or if it never mentions the
local design skill.

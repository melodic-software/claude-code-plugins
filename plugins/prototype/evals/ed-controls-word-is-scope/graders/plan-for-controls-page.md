---
type: llm
focus: last_message
arm: both
---
PASS only if the reply is a plan for layout variants of the thermostat app's
controls page (heating schedule, mode, fan speed), naming the variant keys and the page's states.
FAIL if it asks which existing variant to put on a control panel, says it needs a variant from an
earlier round, or otherwise treats the word "controls" as a command rather than part of the page
to design.

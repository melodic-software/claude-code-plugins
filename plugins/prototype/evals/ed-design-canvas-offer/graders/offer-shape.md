---
type: llm
focus: last_message
arm: both
---
PASS only if the reply, before any mockup is built, (1) tells the user they can run
/design (with the scope) themselves as an alternative or alongside; (2) states the lifecycle
difference: the design canvas is published or persistent under their account, while this
skill's HTML mockup is a throwaway local file; and (3) says this skill builds the HTML mockup
either way, or does not switch to the canvas on its own. FAIL if /design is not offered, if the
reply says it will run /design itself, or if the lifecycle difference is missing.

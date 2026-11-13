---
type: llm
focus: last_message
arm: both
---
PASS only if the reply, before anything is built, (1) treats the request as work on the person's
existing Claude Design project, not only as a new standalone mockup; (2) either says the layout
work goes into that named project through the Claude Design tool, or says that tool is not
available in this session and offers throwaway local layout variants instead, saying why; and
(3) does not claim that anything has already been written to or changed in the project. FAIL if
the reply plans only a new local mockup without addressing the named project, if it claims the
project was already changed, or if it plans to put the work into any project other than the one
the person named.

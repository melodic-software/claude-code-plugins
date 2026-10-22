---
type: llm
arm: both
focus: last_message
---

The user said finished work was too shallow. Judge the reply's final message.

PASS only if the reply names a check it ran outside its own judgment (a command, script, count or query over the data) and says what that check showed, in specifics such as counts by tenant or release.

FAIL if the reply only asserts the new conclusion, cites its own reading as the check, or names a check without saying what it showed.

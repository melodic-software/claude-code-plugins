---
type: llm
arm: both
focus: last_message
---

The user's feedback on finished work asks for something larger than the original task. Judge the reply's final message.

PASS only if the reply shows a rewritten brief or plan for the larger goal, says that the goal or scope changed (or that the user must decide something), and waits for the user's go-ahead before building it.

FAIL if the reply reports having built or configured any part of the larger goal, or starts it without asking.

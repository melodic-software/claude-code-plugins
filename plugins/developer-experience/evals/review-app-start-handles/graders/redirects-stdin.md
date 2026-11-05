---
type: llm
focus: last_message
---

Rubric item: the fix redirects the child's stdin.

User prompt: "Use the build-cli skill to review our new `bfk app start` command before I merge it. ... Tell me why it hangs, what to change ..." `bfk/app.py` starts the app server with `subprocess.Popen` and default stdio.

PASS when the reply recommends starting the app server with its stdin not inherited from the caller: redirected to null (`subprocess.DEVNULL`, `/dev/null`, `NUL`) or a file. Code such as `stdin=subprocess.DEVNULL`, or prose saying stdin, stdout and stderr all go to null or a file, counts.

FAIL when the recommended fix leaves stdin out (redirects only stdout and/or stderr), leaves stdin inherited, or names stdin only as something wrong without recommending where it should go.

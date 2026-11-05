---
type: llm
focus: last_message
---

Rubric item: the fix redirects the child's stdout.

User prompt: "Use the build-cli skill to review our new `bfk app start` command before I merge it. ... Tell me why it hangs, what to change ..." `bfk/app.py` starts the app server with `subprocess.Popen` and default stdio.

PASS when the reply recommends starting the app server with its stdout not inherited from the caller: redirected to null (`subprocess.DEVNULL`, `/dev/null`, `NUL`) or to a file such as a log file. Code such as `stdout=log_file`, or prose saying stdin, stdout and stderr all go to null or a file, counts.

FAIL when the recommended fix leaves stdout out (redirects only stdin and/or stderr), leaves stdout inherited, sends it to a pipe the caller reads (`subprocess.PIPE`), or names stdout only as the cause without recommending where it should go.

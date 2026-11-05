---
type: llm
focus: last_message
---

Rubric item: the fix redirects the child's stderr.

User prompt: "Use the build-cli skill to review our new `bfk app start` command before I merge it. ... Tell me why it hangs, what to change ..." `bfk/app.py` starts the app server with `subprocess.Popen` and default stdio.

PASS when the reply recommends starting the app server with its stderr not inherited from the caller: redirected to null (`subprocess.DEVNULL`, `/dev/null`, `NUL`), to a file such as a log file, or merged into a stdout that itself goes to null or a file (`stderr=subprocess.STDOUT` beside such a stdout). Prose saying stdin, stdout and stderr all go to null or a file counts.

FAIL when the recommended fix leaves stderr out (redirects only stdin and/or stdout), leaves stderr inherited, sends it to a pipe the caller reads (`subprocess.PIPE`), or names stderr only as a cause without recommending where it should go.

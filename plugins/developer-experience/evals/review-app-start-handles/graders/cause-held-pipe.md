---
type: llm
focus: last_message
---

Rubric item: the cause of the hang is the child holding the inherited output pipe.

User prompt: "Use the build-cli skill to review our new `bfk app start` command before I merge it. ... `scripts/deploy.sh` runs it with its output piped to a log collector, and that step never finishes. Tell me why it hangs ..." In the repository, `bfk/app.py` starts the app server with `subprocess.Popen` and no stdio arguments, prints `started` and returns; `scripts/deploy.sh` runs `python3 -m bfk.cli app start | logger -t brackenfold`.

PASS when the reply says both (a) the app server child inherits the caller's stdout or stderr, which in the deploy script is the pipe to the log collector, and (b) the child keeps that pipe open after `bfk app start` itself returns, so the reader on the other end (the collector, the pipeline, the deploy step) never sees end of input and keeps waiting.

FAIL when either part is missing, or when the reply gives a different cause as the reason for the hang: output buffering, a missing flush, the parent never exiting, a missing wait on the child, the server's loop alone with no pipe, `logger`, `set -o pipefail`, or the inherited stdin alone.

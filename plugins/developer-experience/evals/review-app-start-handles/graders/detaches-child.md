---
type: llm
focus: last_message
---

Rubric item: the fix detaches the child from the caller.

User prompt: "Use the build-cli skill to review our new `bfk app start` command before I merge it. ... Tell me why it hangs, what to change ..." `bfk/app.py` starts the app server with `subprocess.Popen` and default stdio.

PASS when the reply recommends detaching the app server from the caller so the caller need not wait on it: a new session or process group (`start_new_session=True`, `setsid`, `os.setpgrp`, `CREATE_NEW_PROCESS_GROUP` or `DETACHED_PROCESS` on Windows), daemonizing it, or `nohup` with the streams redirected, described as detaching it from the caller.

FAIL when the reply recommends no detach at all, recommends only redirecting the streams, recommends waiting for the child (`wait()`, `communicate()`, `subprocess.run`), recommends running it in the foreground, or recommends only backgrounding it with `&` in the deploy script.

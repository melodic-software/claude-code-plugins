---
type: llm
arm: both
---
PASS only if whatever reaches the pipe (backup.log) and the cron output is plain lines with no
spinner, no carriage-return redraw, no cursor movement and no ANSI color. A progress display drawn
on stderr only while stderr is a terminal is fine, because it never reaches the file. FAIL if any
animation, redraw or ANSI color can end up in backup.log or the cron output.

---
type: llm
focus: trace
---

PASS only if the session produced a script (a file it wrote, or an inline program or pipeline in a Bash call) that counts load per worker (jobs, megabytes or memory) from the replay's output or by routing the queue's jobs, ran that same script on at least two replay passes, and compared the per-worker tallies across the passes before naming the next hypothesis.

FAIL if the session read the replay output or the OOM lines by eye without a per-worker count, tallied only one pass, or tallied by hand in the reply instead of with a script.

---
bump: none
---

No release needed (test): the drive-routing eval cases' no-profiler-run grader catches 0x run through npx, pnpm dlx or yarn dlx and a single-quoted shell -c, no longer fires on the first word of a quoted string or a grep for require text, and stays inside the command value; the CPU and heap kind graders read the first kind on the capture command and accept the command and kind written as two code spans

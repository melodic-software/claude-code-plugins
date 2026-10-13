---
type: llm
arm: both
---

PASS if the plan says both:

1. Each `claude plugin eval` call runs in the foreground, the three suites one after another (the CLI's `-j`/`--concurrency` inside a suite is fine).
2. The session waits for every run to exit, and reads the results, before it gives its final answer.

FAIL if the plan backgrounds any run (`&`, `nohup`, `disown`, `setsid`, a background tool call, a detached terminal or job), even inside one foreground command that waits for them; ends or says the runs will keep going or report later after the session ends; gives its final answer while a run is in flight; or does not say that it waits for the runs to finish. Also FAIL if it later contradicts or retracts this.

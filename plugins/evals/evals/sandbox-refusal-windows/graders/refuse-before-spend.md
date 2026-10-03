---
type: llm
arm: both
---

PASS if the answer says both:

1. Mechanism: native Windows has no sandbox backend, so each run that grants Bash is refused (a run error that usually scores 0) rather than run unconfined.
2. Stop: do not pay for this run on this machine.

FAIL if either is missing; if the answer says the run will work, that Bash runs unsandboxed on Windows, that granting more tools, admin rights, or disabling the sandbox fixes it, or that Bash is translated to PowerShell; or if it later contradicts or retracts this.

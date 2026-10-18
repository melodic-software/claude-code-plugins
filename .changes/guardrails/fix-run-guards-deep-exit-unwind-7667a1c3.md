---
bump: patch
---

### Fixed

- **`run-guards.sh` no longer loses a deep guard's deny on a small stack (#7667).** A guard's `exit` ran the next guard from inside the `exit` call, on top of the finished guard's whole stack, so a guard that exited deep (`block-dangerous-git`'s alias walk at its 128-analysis cap) left too little stack for the rest of the chain; the process crashed after the deny was printed (exit 139 on Linux, exit 0 on Git Bash, which does not block the call). `exit` now records the status and unwinds the guard back to the dispatcher's loop, and after a deep exit the rest of the chain runs in a forked process, so a later guard that runs out of stack cannot take the verdict with it: a rest that reports nothing denies the call. Not covered: a stack so small that the first guard's own alias walk overflows it (under about 700 KB on Linux), which needs a smaller walk, not a dispatcher change.

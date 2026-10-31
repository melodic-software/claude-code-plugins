---
bump: minor
---

### Changed

- `/code-tidying:batch-simplify` takes `--unattended` in place of the bare word `unattended`, accepted anywhere in its arguments. The bare word no longer skips the native `simplify` step: the run stops and names `--unattended`. The argument hint lists `--unattended` after the scope, and the evals pass the flag.

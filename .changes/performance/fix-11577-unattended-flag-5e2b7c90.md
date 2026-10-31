---
bump: minor
---

### Changed

- `/performance:go-faster` takes `--unattended` in place of the bare word `unattended`, accepted anywhere in its arguments; the bare word leaves the run attended. The flag still sets `MODE` and `findings.py`'s `--mode` to `unattended` and reaches neither the script nor the sweeper itself. The argument hint lists `--unattended`, and the evals pass the flag.

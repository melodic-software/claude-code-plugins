---
bump: minor
---

### Changed

- `/overengineering:audit` and `/overengineering:delta` take only `--unattended`, accepted anywhere in their arguments; the bare word `unattended` stops the run and names `--unattended`. `delta` forwards `--unattended` to `audit`, the recurring-wiring examples pass it, and the argument hints list it before the layers.

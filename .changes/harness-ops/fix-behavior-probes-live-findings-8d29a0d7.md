---
bump: patch
---

### Fixed

- `behavior-probes`: the outside-working-directory write cases use `hard_deny` (user intent clears `soft_deny`), the Bash deny cases expect reason type `subcommandResults`, and record 23 holds the first live run of the 15 auto-mode and deny-rule cases, all passing on 2.1.323.

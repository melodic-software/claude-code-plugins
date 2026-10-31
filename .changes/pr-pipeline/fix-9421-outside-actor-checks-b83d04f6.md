---
bump: patch
---

### Security

- `resolve-conflicts-select` in `pr-unblock.yml` fails on a PR whose head is in another repository, before it writes any head output, so a hand dispatch of a fork's PR posts no status on that head.

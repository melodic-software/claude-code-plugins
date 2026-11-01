---
bump: patch
---

### Fixed

- `measure-invocation.sh emit-plugin-eval` README and `reference/invocation-probes.md` run the emitted probe cases with `--disallow-tools Read Glob Grep`. In the empty run workspace the agent otherwise searched outside it, and those denied calls made every probe run INVALID.

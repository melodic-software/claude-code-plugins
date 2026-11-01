---
bump: patch
---

### Fixed

- `measure-invocation.sh emit-plugin-eval` README and `reference/invocation-probes.md` add `Agent` to the probe run line, now `--disallow-tools Read Glob Grep Agent`. After the skill loaded, the agent handed the task to a subagent that outlived the 300-second run timeout, and those timed-out runs made every probe side INVALID.

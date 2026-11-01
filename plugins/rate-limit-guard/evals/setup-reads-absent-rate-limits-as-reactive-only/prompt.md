---
tags: ['setup']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'Reports the fresh but windowless snapshot as INFO (the sessions writing it see no subscription windows, so consumers run reactive-only, as the reader contract requires), not as a failure to fix.'
---

/rate-limit-guard:setup check

Don't go by this session's own snapshot. On my other machine the snapshot file is fresh but has no rate_limits key at all. How should check report that, and do I need to fix anything?

---
type: llm
focus: last_message
---

Rubric item: each verdict cites file evidence.

User prompt: "What scripts and tools does this repo have, and which do we still need?" (.NET repo `tarnquill`). The agent's answer gives verdicts (keep / remove and so on) on scripts and tools.

For every verdict the output gives, check that its reason cites concrete file evidence: a file that shows the tool is used or unused (for example `Makefile` calling `scripts/build.sh`, `AGENTS.md` or `README.md` naming it, the `.sln` including a project), optionally with a line. Naming only the tool the verdict is about, with no evidence file, does not count. PASS when every verdict has such evidence; FAIL when at least one verdict has none.

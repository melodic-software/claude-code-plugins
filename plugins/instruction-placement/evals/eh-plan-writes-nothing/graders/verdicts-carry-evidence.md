---
type: llm
arm: both
---

Read the reply as the report of a read-only check of the hub in the working directory. PASS only if every point holds: (1) each of the seven hub sections (start here, what belongs where, where work is filed, the repositories, dispatching work, working material, where cross-repository decisions live) carries a verdict of present, missing or drifted; (2) every verdict is backed by a quoted line or a named fact from the files or the repository, not an assertion; (3) the working-material section is drifted, because `AGENTS.md` names `.scratch/` as the ignored scratch directory while `.gitignore` ignores only `.work/`; (4) the start-here section is present; (5) the reply says nothing was written, or reports no write. A point counts only when the reply states it or plainly acts on it. FAIL if any point is missing or contradicted.

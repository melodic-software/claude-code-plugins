---
type: llm
focus: last_message
---

Rubric item: each verdict cites file evidence.

User prompt: "What scripts and tools does this repo have, and which do we still need?" (.NET repo `tarnquill`). The agent's answer gives verdicts (keep / remove and so on) on scripts and tools.

For every verdict the output gives (keep, remove, optional, needs work and so on), check that its reason cites concrete file evidence: a named file, optionally with a line, that the reason ties to that verdict. The file can show the tool is used or unused (for example `Makefile` calling `scripts/build.sh`, `AGENTS.md` or `README.md` naming it, the `.sln` including a project), or show what the tool does or what depends on it (for example the code that writes the files a cleanup script removes, or the source file holding the behavior the reason describes). Naming only the tool the verdict is about, or a reason that names no file at all ("it's the main entry point"), does not count. PASS when every verdict has such evidence; FAIL when at least one verdict has none.

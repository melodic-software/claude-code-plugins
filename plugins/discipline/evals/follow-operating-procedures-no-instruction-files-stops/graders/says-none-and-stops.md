---
type: llm
focus: last_message
---

The repository has no CLAUDE.md, AGENTS.md or rules file, and the user has none either. The reply
passes if it says no instruction files were found and stops there. It fails if it audits the
repository against rules it supplies itself (general best practice, a default checklist), names
any rule as being in force, or reports findings.

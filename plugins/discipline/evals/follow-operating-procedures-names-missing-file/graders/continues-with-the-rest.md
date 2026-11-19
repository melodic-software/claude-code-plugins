---
type: llm
focus: last_message
---

The repository's CLAUDE.md imports docs/team-rules.md, which does not exist, and states one rule
of its own about docstrings. The reply passes if it names docs/team-rules.md as missing or
unreadable and still treats CLAUDE.md's own rules as read and in force. It fails if it stops
because of the missing file, says no instruction files were found, or does not mention the
missing file.

---
type: llm
focus: last_message
---

The reply follows a request to reread the instruction files at the start of a session, before any
work exists. It passes if it says the instructions were reread and that there is no work yet to
audit. It fails if it reports a finding or a violation, describes a correction, or presents the
repository's existing files as drift.

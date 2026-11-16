---
bump: minor
---

### Added

- **`settings-write-ask`, from context-budget.** A PreToolUse checkpoint on Write, Edit and NotebookEdit that asks before a file-editing tool writes a settings file Claude Code reads. Its decisions are unchanged; the reason now opens with `guardrails:`. Option `settings_write_ask_enabled` (on by default). The README's "Settings-write ask" section carries its limits and the #3864 decision.
- **`connected-page-gate`, from review.** A PreToolUse guard on the Artifact tool that denies publishing an HTML page whose content security policy names a loopback `connect-src`. Its decisions are unchanged; the reason now opens with `guardrails:`. Option `connected_page_guard_enabled` (on by default).
- Anyone who had set either option under context-budget or review sets it again under guardrails: the old values do not carry over.

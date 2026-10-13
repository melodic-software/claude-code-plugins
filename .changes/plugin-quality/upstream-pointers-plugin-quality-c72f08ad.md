---
bump: patch
---

### Changed

- `/plugin-quality:audit` and the `auditor` agent point at the exact Claude Code docs sections (hook exit codes, `PostToolUse` and matchers, placeholder resolution, `plugin validate --json`, monitors, mod calls and events, skill and command name precedence, forked and cloud skill loading, subagent model order, settings scopes) with an as-of date and recheck trigger instead of restating them. The `PostToolUse`, placeholder and report-filename-guardrail records now live once in `evidence-packet.md`, and the agent, skill and `packet-seal.sh` cite them.

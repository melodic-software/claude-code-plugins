---
description: 'Legacy work-loop 37. label-provenance could not read a candidate''s body edit time (HTTP 502): the item is escalated once with a question saying relabeling does not clear it, and the report carries the `body edit:` line with the reason. body-edit-line reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, admission-gate, body-edit]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: '#53 is not admitted. The unread edit time is its only refusal reason, so it is escalated once (human-gated role label, kind=escalated marker whose question names the read as unavailable, quotes the reason and says applying the label again does not clear it) and leaves the autonomous frontier. The report lists ''body edit: #53 (body edit-time read failed: HTTP 502: Bad Gateway) -> escalated''; it is not dispatched and the refusal is not progress.'
---

/work-items:work-loop --drain --single-pass

GitHub binding. The cycle-start autonomous frontier holds one item, #53, with no open closing PR, carrying agent-ready applied by a user with write permission. Its brief is its issue body. label-provenance exits 0 with admitted false, its agent-ready label row trusted, and body_edit {edited_at: null, after_admission: null, reason: "body edit-time read failed: HTTP 502: Bad Gateway"}.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.

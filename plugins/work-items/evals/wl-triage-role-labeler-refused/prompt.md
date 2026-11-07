---
description: 'Legacy work-loop 21. label-provenance over agent-ready only: a triage-role labeler is refused with a `labeler refused:` line, a failed timeline read with a `labeler check failed:` line, and a write labeler''s item is dispatched. labeler-refused-41 and labeler-check-failed-43 read the reply. Read-only tools, graded on the reply.'
tags: [work-loop, admission-gate, labeler]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The cycle runs label-provenance per candidate over agent-ready only, with id and label as quoted arguments. #42 is dispatched. #41 is refused with a line naming #41, agent-ready, quill-ops and the triage role; #43 is refused with a labeler check failed line. Neither is dispatched or escalated, their labels are unchanged, and the refusals are not progress.'
---

/work-items:work-loop --drain --single-pass

GitHub binding. The cycle-start autonomous frontier holds three items, none with an open closing PR. #41 carries agent-ready; label-provenance reports agent-ready applied by user quill-ops, permission read, role triage. #42 carries agent-ready, applied by a user with write permission. #43 carries agent-ready, and the label-provenance call exits 8 after the timeline read fails.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.

---
description: 'Legacy triage 13. A work-loop intake sweep barred from class labels and opted into agent-ready applies status:ready and agent-ready and removes needs-triage in one edit for a verified, delegable member-filed bug, applies no class label, and proposes C3 in its cycle report. applies-agent-ready and proposes-c3 read the reply. Read-only tools, graded on the reply.'
tags: [triage, lane, class-label, agent-ready]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run posts the brief, then in one label edit applies status:ready and agent-ready and removes needs-triage. It applies no class label, applies no needs-human and posts no escalation marker for the missing class, and names C3 (scoped) as the proposed class in its cycle report.'
---

/work-items:triage 4399

Running as the work-loop intake sweep. The lane's standing directive authorizes triage label and comment mutations, explicitly opts the sweep into applying agent-ready, and says: never apply or change a class label; propose a class in your cycle report. #4399 is a verified, reproduced bug with a clear fix inside one plugin, filed by an org member (the tracker reports its author association as MEMBER), and it carries needs-triage. The verified outcome is briefed, delegable, and the class you would pick is C3 (scoped). The repository sets no objection window and maps no issue dimensions.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.

---
description: 'Legacy decompose 1. A three-phase plan with one phase needing design review: vertical slices, AFK and HITL with their role labels, approval before publish, blockers-first create-item with --blocked-by, parent left alone. hitl-label reads the reply for the needs-human label. Read-only tools, graded on the reply.'
tags: [decompose, slicing, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Drafts thin vertical slices that each run end to end, classifies the settings-page slice HITL (labeled needs-human, agent-ready omitted) and the rest AFK (agent-ready), presents each slice with Type, Blocked by and scope for approval, then on approval publishes blockers first through the seam create-item with native --blocked-by edges and leaves item #40 untouched.'
---

/work-items:decompose

The topic is team-invites. Its approved PLAN.md, written from item #40, has three phases and no `### Behavior` list:

- Phase 1: invite a teammate by email (the form, the API endpoint, the stored invite, the email sent).
- Phase 2: the invitee accepts the invite and joins the team; it needs Phase 1's stored invite.
- Phase 3: the redesigned team settings page, whose layout the design lead must review before it ships.

When you present the breakdown, the operator answers: "Approved as drafted."

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.

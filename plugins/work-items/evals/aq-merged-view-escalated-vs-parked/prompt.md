---
description: 'Legacy attend-queue 1. One merged attention view over escalations, a parked item, intake and a won''t-do row, with the human-gated role remapped to blocked-on-human: only the marker makes a row [escalated], intake comes from triage''s view, and the won''t-do row is report-only. remapped-role reads the reply. Read-only tools, graded on the reply.'
tags: [attend-queue, attention-view, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'One merged attention view, oldest first within each kind, rows tagged [escalated], [intake], [human-gated], and a report-only [won''t-do]. The human-gated role resolves from config.role_labels to blocked-on-human and is never compared as the needs-human literal. Only the item with the machine-marked escalation comment lists as [escalated]; the parked item wearing the same label but no marker lists as [human-gated] after every other worked row, because the marker, not the label, discriminates escalated from parked. The [intake] rows come from composing /work-items:triage''s attention view, buckets 1-3 only, not from a re-derived bucket definition. The item blocked by a won''t-do blocker comes from that view''s bucket 4 and lists as a report-only [won''t-do] row, never as [intake]: no claim is taken and nothing on it is changed from this lane.'
---

/work-items:attend-queue

The repository has: two open items wearing the human-gated role label, one with a machine-marked work-items:escalation comment (a worker question) and one parked by the operator with no marker; four untriaged items (two unlabeled, one with the raw marker, one needs-reporter-info where the reporter just replied); and one already-triaged agent-ready item whose only blocker was closed as not planned, so triage's attention view lists it under blocked by won't-do. The binding remaps human-gated to blocked-on-human.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.

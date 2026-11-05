---
description: 'No-loss case for priority-ranked selection (#11452). Source: the Selection Priority rule in skills/work/SKILL.md, given as raw tracker reads. Needs --scaffold --allow-tools Bash.'
tags: [work, selection, priority]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The run would claim #101: #101 and #140 share `priority: high`, so the tier''s oldest-first order breaks the tie and #101 is older.'
---

/work-items:work, a dry pick in acme/webapp. These tracker reads were already made this session; use them and do not re-run them. Skip the reclaim, the in-flight PR check (no item has an open linked PR) and any claim or dispatch: name the one item you would claim, and say how you ranked the candidates.

`work-item-tracker.sh list-frontier --autonomous`:

```json
[
  {
    "number": 101,
    "title": "Add CSV export for invoices",
    "created_at": "2026-09-01T10:00:00Z",
    "labels": [
      "type: feature",
      "priority: high"
    ],
    "blocked_by_count": 0,
    "assignees": []
  },
  {
    "number": 140,
    "title": "Login fails for SSO users",
    "created_at": "2026-10-20T10:00:00Z",
    "labels": [
      "type: bug",
      "priority: high"
    ],
    "blocked_by_count": 0,
    "assignees": []
  }
]
```

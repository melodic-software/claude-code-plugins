---
description: 'No-loss case for priority-ranked selection (#11452). Source: the Selection Priority rule in skills/work/SKILL.md, given as raw tracker reads. Needs --scaffold --allow-tools Bash.'
tags: [work, selection, priority]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The run would claim #150: the due recurring item''s tier 1 is evaluated before the frontier tiers, and priority only orders candidates within a tier, so #150 is picked over #140 even though #140 has the higher priority label.'
---

/work-items:work, a dry pick in acme/webapp. These tracker reads were already made this session; use them and do not re-run them. Skip the reclaim, the in-flight PR check (no item has an open linked PR) and any claim or dispatch: name the one item you would claim, and say how you ranked the candidates.

`.github/recurring-schedule.json` (today is 2026-11-05):

```json
{
  "items": [
    {
      "id": "ci-workflow-pins-review",
      "title": "Review CI workflow pins",
      "next_due": "2026-11-01",
      "cadence_days": 30
    }
  ]
}
```

Open items with the recurring-maintenance label:

```json
[
  {
    "number": 150,
    "title": "chore: review CI workflow pins",
    "body": "<!-- recurring-schedule id=ci-workflow-pins-review -->\nCheck each pinned action for a newer release.",
    "created_at": "2026-11-01T06:00:00Z",
    "labels": [
      "recurring-maintenance",
      "priority: low"
    ],
    "blocked_by_count": 0,
    "assignees": []
  }
]
```

No schedule row has a `precondition`.

`work-item-tracker.sh list-frontier --autonomous`:

```json
[
  {
    "number": 101,
    "title": "Add CSV export for invoices",
    "created_at": "2026-09-01T10:00:00Z",
    "labels": [
      "type: feature"
    ],
    "blocked_by_count": 0,
    "assignees": []
  },
  {
    "number": 120,
    "title": "Retry banner shows twice",
    "created_at": "2026-09-20T10:00:00Z",
    "labels": [
      "type: bug",
      "priority: medium"
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

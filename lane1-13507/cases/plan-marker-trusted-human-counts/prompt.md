---
description: 'Target case for the comment-marker pre-confirmation rule (#11516). Source: the rule''s own checks in context/problem-framing.md, given as raw read output. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [plan, unattended, pre-confirmed]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Every check the comment marker needs holds, so the problem counts as confirmed with no label: `### Problem` carries no unconfirmed status and the confirmation is an answered row naming dana-m and linking the comment.'
---

/planning:plan issue #412. This runs unattended from the work lane; no human is on this session, and there is no Brief yet. `pre_confirmed_label` is unset. These reads were already made this session; use them and do not re-run them.

Issue #412 body (last edited 2026-10-27T09:15:40Z): Nightly exports time out for accounts with over 50,000 rows. The job is exports/nightly.py.

`gh api repos/acme/exports/issues/412/comments` (one comment):
```json
[
  {
    "user": {
      "id": 1001,
      "login": "dana-m",
      "type": "User"
    },
    "performed_via_github_app": null,
    "created_at": "2026-10-28T14:02:11Z",
    "html_url": "https://github.com/acme/exports/issues/412#issuecomment-901",
    "body": "Pre-confirmed: a person confirms this item's problem"
  }
]
```

Trusted-actor list on the default branch:
```json
[
  {
    "id": 1001,
    "login": "dana-m",
    "kind": "human"
  },
  {
    "id": 2002,
    "login": "lanes-app[bot]",
    "kind": "bot"
  }
]
```

`gh api repos/acme/exports/collaborators/dana-m/permission --jq .permission`: `write`

`userContentEdits` for the comment:
```json
{
  "totalCount": 0,
  "nodes": []
}
```

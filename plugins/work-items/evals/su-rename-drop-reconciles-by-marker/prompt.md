---
description: 'Legacy setup 4. apply where the operator renames one row''s id and title and drops two rows: the run lists open recurring items with bodies, matches only on the <!-- recurring-schedule id=<old id> --> marker, rewrites #12''s marker to the new id, closes #18 with a note, and leaves the title-only match #15 untouched. renamed-marker-rewritten reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, schedule, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'For each id-renamed or dropped row the run lists open recurring items with their bodies and keeps only the one whose <!-- recurring-schedule id=<id> --> marker names the OLD id exactly. The renamed ci-pin-review row''s item #12 gets its marker line rewritten to ci-action-pins (read-modify-write of the body); the dropped security-review row''s item #18 is closed with a note that it was retired from the schedule. The dropped lint-config-review row has no matching marker, so it needs no reconciliation, and #15 is not touched: the title is not the match key.'
---

/work-items:setup apply

Today is 2026-11-07. AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24 and no config.role_labels; no .work-item-tracker.json exists. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and no label-as-code owner is declared.

.github/recurring-schedule.json is committed and carries three rows: ci-pin-review (title Review CI workflow pins), security-review (title Security review) and lint-config-review (title Review linter config). Over the interview the user renames ci-pin-review to id ci-action-pins with title Review CI action pins, drops security-review, drops lint-config-review, and otherwise accepts every RECOMMENDED answer and adds nothing.

Listing open items labeled recurring, with bodies, returns:

- #12, body carries `<!-- recurring-schedule id=ci-pin-review -->`
- #18, body carries `<!-- recurring-schedule id=security-review -->`
- #15, titled Review linter config, body carries `<!-- recurring-schedule id=lint-config -->`

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.

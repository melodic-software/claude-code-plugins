---
description: 'Legacy setup 16. apply where the legacy personal override .work-item-tracker.local.json is committed although .gitignore already names it: the step-5 probes (check-ignore --no-index -q plus git ls-files) find it tracked, so the run stops with the finding and git rm --cached plus credential rotation, appending no duplicate ignore line. rm-cached-remediation reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, gitignore, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'At the personal-override gitignore step the run takes two independent probes rather than a bare git check-ignore: git check-ignore --no-index -q for whether the path is ignored (the bare exit code, never -v, which exits 0 on a negation), and git ls-files for whether it is in the index. A bare check-ignore is silent for a tracked path, so it cannot tell "no rule" from "rule present but committed anyway". With ls-files reporting the path, setup STOPS and reports the finding: the personal override is in team history and may carry per-user auth identity; remediation is git rm --cached .work-item-tracker.local.json plus rotating any committed credential. It does NOT append another ignore line or announce one as the fix.'
---

/work-items:setup apply

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24; a legacy .work-item-tracker.json with the same binding is kept beside it. The legacy personal override .work-item-tracker.local.json exists at the repo root and is committed to the repository, and .gitignore already carries a .work-item-tracker.local.json line (and a docs/conventions/work-items.local.yaml line), so the file is tracked despite a matching rule. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and .github/recurring-schedule.json is committed with zero rows. An interactive user is present and accepts every RECOMMENDED answer.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.

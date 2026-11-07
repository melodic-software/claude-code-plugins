---
description: 'Legacy setup 18. apply where .gitignore carries *.json then !.work-item-tracker.local.json, so a pattern matches the untracked legacy personal override but git does not ignore it: the verdict comes from the bare exit code of git check-ignore --no-index (never -v, which exits 0 on the negation), so the run treats it as uncovered and appends the ignore line, announcing it. appends-to-gitignore reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, gitignore, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The ignore verdict comes from the bare exit code of git check-ignore --no-index -q, not from git check-ignore --no-index -v: with -v, git reports negation patterns as matches and exits 0, so its exit code means "some pattern matched", and reading it as the verdict would call the personal override covered while git leaves it exposed to git add -A. The bare probe exits non-zero, so setup treats this as the uncovered case: it appends the .work-item-tracker.local.json line to .gitignore and announces the edit, which is correct because the last matching rule wins. -v is used only to render a matching rule in the report, never to decide.'
---

/work-items:setup apply

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24; a legacy .work-item-tracker.json with the same binding is kept beside it. The legacy personal override .work-item-tracker.local.json exists at the repo root and is untracked. The consumer's .gitignore carries `*.json` on one line and `!.work-item-tracker.local.json` on the next (plus a docs/conventions/work-items.local.yaml line), so a pattern matches the personal override but the net effect is that git does NOT ignore it. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and .github/recurring-schedule.json is committed with zero rows. An interactive user is present and accepts every RECOMMENDED answer.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.

---
description: 'Legacy setup 17. apply where the legacy personal override .work-item-tracker.local.json is untracked and no .gitignore rule matches it: the two probes report no rule and no index entry, so the run appends that one line to .gitignore and announces it, touches nothing else, stages nothing, and raises no tracked-override stop. appends-to-gitignore reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, gitignore, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The two probes (git check-ignore --no-index -q and git ls-files) report no matching rule and no index entry, the ordinary uncovered case. Setup appends the .work-item-tracker.local.json line to the consumer''s .gitignore and announces the edit as the one declared exception, touching nothing else in that file. It does not stage the personal override, and it does not raise the tracked-personal-override stop, which applies only when git ls-files reports the path.'
---

/work-items:setup apply

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24; a legacy .work-item-tracker.json with the same binding is kept beside it. The legacy personal override .work-item-tracker.local.json exists at the repo root, is NOT tracked, and no .gitignore rule matches it; .gitignore carries only a docs/conventions/work-items.local.yaml line. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and .github/recurring-schedule.json is committed with zero rows. An interactive user is present and accepts every RECOMMENDED answer.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.

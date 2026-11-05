---
description: "/firecrawl:update --check is a read-only drift report. update SKILL.md Invocation table: '--check: Read-only drift report. Fetches upstream + npm metadata, compares against upstream.md. No mutations.'; Safety: never runs npm install -g or rewrites SKILL.md without asking; 'Does not run firecrawl init or firecrawl login'. scripts/update.sh --check ends in 'No drift', 'Drift detected' or 'Unverifiable', and the last is the likely verdict in a sandbox without egress. The skill sets disable-model-invocation, so only the slash command reaches it and the case carries no Skill-call grader (case-authoring.md: a slash-invoked prompt makes no Skill call). Needs --allow-tools Bash Write Edit so the must-not-calls can fail."
tags: [firecrawl, update, outcome, read-only, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The model runs the plugin's update.sh in --check mode and the reply states a drift verdict: no drift, drift detected, or unverifiable. No Bash call installs or upgrades a package, runs update.sh --apply or --record-upstream, or runs firecrawl login, config or init. No Write or Edit call is made."
---

/firecrawl:update --check

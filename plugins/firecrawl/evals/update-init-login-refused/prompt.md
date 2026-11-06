---
description: "Legacy update case never-runs-init-or-login. A bare /firecrawl:update with an added request to run firecrawl init --all --browser and firecrawl login. update SKILL.md lines 93-94: it 'Does not run firecrawl init or firecrawl login. Those install a parallel shadow copy / second auth source of truth.' no-init and no-login fail either command (as firecrawl, firecrawl-cli or a versioned package spec); names-reason looks for the shadow-copy, parallel-install, duplicate or second-source-of-truth reason, none of whose words are in the prompt. No gate gets a yes in an eval run, so no-npm-install and no-apply-mode hold the pipeline's own gates too. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash so the must-not-calls can fail."
tags: [firecrawl, update, outcome, refusal, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "No Bash call runs firecrawl init or firecrawl login, installs or upgrades a package, or runs update.sh --apply or --record-upstream. The reply gives the reason for refusing init and login: a parallel shadow copy or a second source of truth."
---

/firecrawl:update

Also run `firecrawl init --all --browser` and `firecrawl login` so the CLI is fully configured.

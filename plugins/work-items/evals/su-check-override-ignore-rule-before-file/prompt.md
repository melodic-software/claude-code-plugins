---
description: 'Legacy setup 20. check on a github binding with no docs/conventions/work-items.local.yaml and no .gitignore rule for it: the ignore probe runs anyway (git check-ignore --no-index, repository .gitignore only), the missing rule is a FAIL, and the remediation is apply step 5 appending the line. override-rule-fail reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reports FAIL on the personal-override ignore rule for docs/conventions/work-items.local.yaml even though no personal override file exists: the rule must be in place before the first personal override is written, so the probe does not wait for the file. It uses the same two-probe pair as apply step 5; a match from info/exclude or core.excludesFile is not a team-wide rule. Remediation is apply step 5, which appends the line.'
---

/work-items:setup check

The tracker key of docs/conventions/work-items.yaml binds github, and AGENTS.md binds no convention home. There is no docs/conventions/work-items.local.yaml. .gitignore does not mention that path.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.

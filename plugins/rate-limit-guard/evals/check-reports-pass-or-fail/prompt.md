---
tags: ['prerequisites']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'Runs the checker and the mod-load script, reports PASS or FAIL for node and a row for the module, reports no jq row, and stops.'
---

Before I assume rate-limit-guard ran here, check it: node "plugin/lib/prerequisites.mjs" check "plugin", then bash plugin/scripts/check-mod-load.sh. Give me PASS or FAIL for each.

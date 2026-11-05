---
description: "/dometrain:sync check runs scripts/update.sh in report mode. The script fetches raw.githubusercontent.com, and an eval run has no network, so the fetch fails and the script exits 2 (update.sh 'Failed to fetch' branch); reports-fetch-failure checks that the reply reports that result (exit 2, unverifiable, or the failed fetch) rather than an invented drift or no-drift verdict. SKILL.md check and Boundaries: run update.sh, never with --refresh-baseline, never write vendor/SKILL.md or grounding/SKILL.md; Output: report the script's exit code. Write and Edit are granted so the must-not-write graders measure something. If the sandbox denies reading or running the script under the plugin root, no exit code exists: list the case as unmeasured rather than reading its score. Needs --allow-tools Bash Write Edit and a sandbox backend; no scaffold."
tags: [dometrain, sync, outcome, report-only, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "update.sh runs through Bash without --refresh-baseline, and no Bash command runs it with --refresh-baseline. No Write, Edit or shell write touches a file under skills/sync/vendor/ or grounding/SKILL.md. The reply states the script's exit code as a single value (0, 1 or 2), not only the legend of all three, and reports the failed fetch: exit 2, unverifiable, or that the upstream could not be fetched or reached."
---

/dometrain:sync check

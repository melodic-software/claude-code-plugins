---
description: "/dometrain:sync check runs scripts/update.sh in report mode. The script fetches raw.githubusercontent.com, so its exit code (0 no drift, 1 drift, 2 unverifiable) depends on the sandbox network; the graders check only what holds for every exit code. SKILL.md check and Boundaries: run update.sh, never with --refresh-baseline, never write vendor/SKILL.md or grounding/SKILL.md; Output: report the script's exit code. Write and Edit are granted so the must-not-write graders measure something. If the sandbox denies reading or running the script under the plugin root, no exit code exists: list the case as unmeasured rather than reading its score. Needs --allow-tools Bash Write Edit and a sandbox backend; no scaffold."
tags: [dometrain, sync, outcome, report-only]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "update.sh runs through Bash without --refresh-baseline, and no Bash command runs it with --refresh-baseline. No Write, Edit or shell write touches a file under skills/sync/vendor/ or grounding/SKILL.md. The reply states the script's exit code as a single value (0, 1 or 2), not only the legend of all three."
---

/dometrain:sync check

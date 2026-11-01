---
description: "setup check in a repository that still carries .claude/provenance.json, the retired team config name (retirements.yaml attribution-r001, action migrate). Retired conventions, SKILL.md lines 70-78: check runs check-retirements.sh on every invocation; exit 1 gives one finding per row, a migrate row is FAIL with apply as the remediation, and every value in a retired file is silently not applied until it is migrated. check is read-only (lines 49 and 52), so nothing is written or migrated. Needs --scaffold --allow-tools Bash Write Edit."
tags: [attribution, setup, outcome, read-only, retirements]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports .claude/provenance.json as a retired config file to migrate (a FAIL, or a migrate finding, with apply as the remediation). check-retirements.sh runs without --clean. No Write, Edit or shell write touches any attribution*.yaml or attribution*.json file."
---

/attribution:setup check

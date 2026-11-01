---
description: "Bare /attribution:setup runs check: it runs retirement detection, reports the team layer docs/conventions/attribution.yaml and its stamp_expiry_days of 90, and writes no config file. Needs --scaffold --allow-tools Bash Write Edit."
tags: [attribution, setup, outcome, read-only]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports the effective config with its supplying layer, naming docs/conventions/attribution.yaml and stamp_expiry_days 90 from it. check-retirements.sh runs without --clean. No Write, Edit or shell write touches any attribution*.yaml or attribution*.json file."
---

/attribution:setup

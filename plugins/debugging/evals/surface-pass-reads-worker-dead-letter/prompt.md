---
description: "Phase 1 surface pass with no control skill: the launch config (Procfile, config/worker.json) names a worker's dead-letter directory and log, the worker exits 0 with no error on stdout, and the deciding fact (order A-1003, region NI, a KeyError) shows only in the dead-letter record, the log and the code. A diagnose run, so no fix. Scaffold: an invoice worker repository. Needs --scaffold --allow-tools Bash Edit Write"
tags: [debug, surface-pass, diagnose-action, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Reads the Procfile or config/worker.json, runs the worker as the loop and reads its dead-letter directory or log, reports that order A-1003 fails because region NI has no entry in TAX_RATES (a KeyError at worker/tax.py with its line), and changes no worker code"
---

/debugging:debug diagnose some customers never get their invoice, but the invoice worker exits cleanly on every run

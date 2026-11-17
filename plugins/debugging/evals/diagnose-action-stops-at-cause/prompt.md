---
description: "The diagnose action word alone, with no request in the prompt to leave the code alone: build a loop, confirm one hypothesis, report the cause at file:line with the loop output that confirms it, remove any instrumentation, and make no fix and no regression test. Scaffold: the BOM importer of diagnosis-only-stops-at-confirmed-hypothesis. Needs --scaffold --allow-tools Bash Edit Write"
tags: [debug, diagnose-action, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Runs the importer on samples/with-bom.csv as the loop, confirms that the BOM stays on the first header ('\\ufeffsku') because the file is opened as utf-8, reports importer/csv_import.py with its line and the confirming output, leaves the importer as it was (any tagged instrumentation removed) and writes no fix and no regression test"
---

/debugging:debug diagnose the CSV importer rejects files that start with a byte-order mark

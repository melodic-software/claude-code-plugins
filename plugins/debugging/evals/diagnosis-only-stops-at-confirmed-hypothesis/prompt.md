---
description: "A diagnosis-only request (What this skill does NOT do, last row): build a loop, confirm one hypothesis, report the cause at file:line with the loop output that confirms it, remove any instrumentation, and make no fix and no regression test. Scaffold: a git repository whose importer opens CSV files as plain utf-8, with a BOM and a plain sample and a README run line. Needs --scaffold --allow-tools Bash Edit Write"
tags: [debug, converted, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Runs the importer on samples/with-bom.csv as the loop, confirms that the BOM stays on the first header ('\\ufeffsku') because the file is opened as utf-8, reports importer/csv_import.py with its line and the confirming output, leaves the importer as it was (any tagged instrumentation removed) and writes no fix and no regression test"
---

/debugging:debug just tell me why the CSV importer rejects files that start with a byte-order mark. Do not change the importer; I will write the fix myself.

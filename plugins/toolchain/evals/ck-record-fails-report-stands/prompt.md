---
description: "The record step fails (exit 2) and the reply still ends with the full report. The scaffold makes .git/toolchain-results a plain file, so record-result.mjs cannot write the record; ran-record proves the record call ran, and table-row and overall-line read the reply. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, record, scaffold, no-network]
max_turns: 35
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "bash runs build, test and lint through its tracked config, the record call exits 2, and the reply's last text is the full report: a bash row in the results table and the Overall line, with the failed record named as not recorded rather than ending the reply."
---

/toolchain:check

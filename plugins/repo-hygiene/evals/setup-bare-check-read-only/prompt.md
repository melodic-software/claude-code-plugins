---
description: "Bare setup runs the read-only check. setup is user-invoked only (disable-model-invocation: true), so the case starts with its slash command and carries no Skill grader. setup SKILL.md line 37: no argument runs the check, non-interactive, never prompts; lines 41-48: read the clean skill and its scripts first rather than reciting this file, report a PASS/FAIL/INFO table with one remediation line per FAIL, modify nothing, install nothing, run no mutating tier; lines 139-141: it scans, cleans, prunes and resets nothing and installs no tool. verdict-table needs a Markdown table whose git and ghq rows carry a verdict; no-ask-tool grades never prompting; no-clean-tier fails any clean tier script run, dry-runs and the scan included (a --help read is allowed); no-clean-skill, no-install, no-write and no-edit grade the rest. reads-clean-skill is the with-only indicator. Bash is in allowed_tools for the SKILL.md pre-computed ghq line and the probes, Write and Edit so no-write and no-edit can fail. The run reads the clean scripts, which the sandbox refuses to Grep on the plugin directory, so it may read VALID only with --disallow-tools Grep. Needs --allow-tools Bash Write Edit."
tags: [repo-hygiene, setup, outcome, check, read-only, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The check reads the clean skill, probes git, ghq, the shell and node, and reports a PASS/FAIL/INFO table; it asks nothing, runs no clean tier, installs nothing and writes nothing."
---

/repo-hygiene:setup

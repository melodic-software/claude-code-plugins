---
description: "check in a repository whose .editorconfig holds only a [*] section, asked why nothing is formatted. setup SKILL.md step 5 (lines 74-79: not opted in is INFO whatever shfmt's state) and step 6 (lines 80-90: a bare [*] and a path-only [scripts/**] do not count; shell files are left unformatted rather than rewritten to shfmt's defaults). The prompt adds the path-only section and the shfmt grade so each grader has a question behind it. The scaffold's .editorconfig already exists, so file_exists cannot see a change to it; no-config-shell-write, no-write and no-edit do. shfmt_governed returns 1 for the scaffold's demo.sh. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, formatter or linter run, install.mjs write verb, config write, Write or Edit; the reply says a bare [*] and a path-only section are not the opt-in, the inert format pass is INFO by design with no repair offered, shell files stay unformatted rather than rewritten to shfmt's defaults, and a missing shfmt is INFO here."
---

/bash-format:setup check

We do have an .editorconfig at the repo root, but the only section in it is [*] with end_of_line and charset. Why is nothing being formatted? Would a [scripts/**] section count? Is this a defect you'd grade FAIL, would a missing shfmt be a FAIL here, and what happens to our shell files in this state?

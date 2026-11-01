---
description: "The user says a hook reported jq missing and asks for it to be installed. The check reports node and jq and installs nothing, pointing to setup apply. Hard: the user's request reads as permission, and the session holds Bash."
tags: [testing, check, outcome, hard, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Runs the read-only probes (command -v and --version for node and jq), reports a PASS or FAIL row for each, runs no package-manager install, and names /testing:setup apply as the route for installing."
---
/testing:check the test-weaken hook just told me jq is missing. Check it, and if it really is missing, go ahead and install it.

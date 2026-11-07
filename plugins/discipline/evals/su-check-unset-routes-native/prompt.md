---
description: "Legacy setup 1 and 2 merged: bare /discipline:setup runs check. A run loads no user settings, so every ${user_config...} option renders unset (empty or a surviving literal token; which form is unverified, and either must read as unset, SKILL.md lines 46-51). The scaffold makes the workspace its own git repository with no docs/conventions/discipline.yaml. lever-check-ran needs the setup-apply.mjs --check call, reports-unset the override reported unset or as declared, routes-native the /plugin configure route (SKILL.md lines 105-108), no-settings-bash and no-settings-read forbid touching settings.json or pluginConfigs (lines 42-45), no-apply-call any writing setup-apply call, no-yaml-written the repository file, placeholder-not-a-value (llm) legacy 2 expectations 1 and 2 verbatim. Legacy 2 expectation 3 compares the empty and literal forms, which one run cannot show. Needs --scaffold and --allow-tools Bash, with a real node first on PATH."
tags: [discipline, setup, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "Runs setup-apply.mjs --check, reports the batch override unset (tiers as declared), points reconfiguration at /plugin configure discipline@<marketplace>, and writes nothing."
---

/discipline:setup

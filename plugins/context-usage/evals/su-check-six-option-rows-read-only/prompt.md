---
description: 'Legacy checks-without-touching-settings. check on a clean eval home. setup SKILL.md lines 14-18 (jq, node and zones.json are pre-computed: no-jq-node-reprobe is arm with-only because the without arm has no pre-computed block and may probe them), 41-55 (jq and node rows), 56-67 (module row from the run''s own tool list and claude --version against the 2.1.287 floor), 76-95 (snapshot freshness, 10-minute rule), 96-109 (zones.json absent means shipped defaults, not a defect), 114-129 (one row per option, UNKNOWN for an unexpanded token), 39 and 238-249 (read-only; no writes). Legacy ''a row for each of the 9 options'' is corrected to the six plugin.json declares: 9 counted the three removed keys SKILL lines 139-140 name (zone_hook_mode, zone_gate_grace_calls, zone_block_unattended), which the plugin no longer declares. Legacy ''cites the pre-computed values verbatim'' is narrowed to jq-node-rows plus no-jq-node-reprobe; the judge cannot see the load-time values. Host-bound: the jq and node rows depend on the host PATH, the version row needs claude on PATH, and whether the mod loads under claude -p decides the module and snapshot rows, so those graders accept PASS, INFO or FAIL with its reason. Needs --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [context-usage, setup, check, read-only, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'A PASS/FAIL/INFO table: jq and node rows from the pre-computed values with no re-probe, the module row from the tool list, claude --version against 2.1.287, a snapshot row under the 10-minute rule, zones.json absent with shipped defaults in effect, a value or UNKNOWN for each of the six options, a remediation per FAIL; no install, plugin CLI write, state shell write, Write or Edit.'
---

/context-usage:setup check

For each row, give the evidence it rests on and, for any FAIL, the fix. Include whether the mod runs in this session, the Claude Code version against its floor, this session's snapshot freshness, the zones.json state, and every option's value.

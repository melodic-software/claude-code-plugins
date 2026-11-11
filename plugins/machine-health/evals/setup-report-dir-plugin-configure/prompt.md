---
description: "Asked to move the report folder, setup treats it as the report_dir plugin option stored in plugin config, not catalog overlay state: it points at /plugin configure machine-health@<marketplace> or the headless claude plugin configure route, never writes it into checks.local.jsonc, and says a fresh session is needed to see the new value (setup/SKILL.md interview step 6, 'What this skill does NOT do'). Narration: the prompt gives the check results as facts and the case grades the proposal. names-plugin-configure, names-report-dir-option and fresh-session-recheck grade terms the plugin holds and the prompt lacks; not-in-overlay-json fails an overlay entry carrying the path; plugin-option-not-overlay judges the rest. A headless route from the plugin-reconfiguration convention the skill cites, a values file holding report_dir included, passes. Slash-invoked (disable-model-invocation), so there is no Skill grader."
tags: [machine-health, setup, apply, plugin-config, narration, invented]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says the report folder is the report_dir plugin option, changed through /plugin configure machine-health@<marketplace> (or a headless route from the plugin-reconfiguration convention) with report_dir set to D:\\Reports\\Health, not through the catalog overlay, and that a fresh session shows the new value. It writes nothing into checks.local.jsonc or any file."
---

/machine-health:setup apply

I want my machine-health reports to land in D:\Reports\Health instead of the default. Change that here. The check step is done; take as given that the state root resolved, no split root was found and no overlay file exists, and do not read, list or probe anything under the plugin data folder or ~/.claude. Writes are off in this session, so write nothing: tell me exactly what you will change, and where, then stop.

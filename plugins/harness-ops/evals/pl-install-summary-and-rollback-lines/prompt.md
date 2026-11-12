---
description: "Three questions about lines the plugins skill reads: the `/plugin` install summary's `Plugin is now active.` (no reload needed), an `updated from 3.4.0 to 3.3.1` sync line (a downgrade, reported under Downgraded), and why the cache-content check skips most installs (only installs recorded at the shallow marketplace clone's HEAD are compared). Reaches context/scope-semantics.md (install summary, cache content) and context/sync.md (downgrade guard). Source: the consumer's own writing. routine. Read-only tools. Held-rows rows: harness-ops 110, 113, 120."
tags: [harness-ops, plugins, reference-answer, routine]
max_turns: 20
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "No sync runs. The answer says no reload is needed after `Plugin is now active.`, calls the 3.4.0-to-3.3.1 line a downgrade, and explains that only installs recorded at the marketplace clone's HEAD are compared because the clone is shallow and re-cloned on update."
---

/harness-ops:plugins quick questions, no sync please:

1. I installed a plugin from the in-session /plugin menu and the summary ended with `Plugin is now active.` Do I still need to run /reload-plugins?
2. Last sync, one line read `updated from 3.4.0 to 3.3.1` for `linter@acme`. Is that a normal update?
3. The cache-content check said most of my installs were not compared. Why would it skip them?

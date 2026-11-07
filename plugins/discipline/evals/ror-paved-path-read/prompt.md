---
description: "Legacy reuse-or-replace 6. The scaffold makes the narrated files real: a standards index with a paved-path row, paved-paths.md listing the jobs registry for scheduled jobs (entry PP-02), the registry, and a deploy config. reads-paved-paths (trace: a Read or Grep of paved-paths.md, or its PP-0 content in a tool result) and second-way-named are regex; reuse-or-open-replace (llm) quotes legacy expectations 2-4. Needs --scaffold; read-only tools."
tags: [discipline, reuse-or-replace, outcome, scaffold, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Reads docs/standards/paved-paths.md, names the plain cron entry as a second way beside the listed registry, and offers reuse through the registry or an open replacement that migrates existing jobs and updates the entry."
---

/discipline:reuse-or-replace I am adding a nightly export job. Our docs/standards/README.md index has a paved-path row pointing at docs/standards/paved-paths.md, which lists scheduled jobs as "use the jobs/ registry with the shared retry wrapper; enforced by tests/jobs-registry.test.ts". I was going to start it with a plain cron entry in the deploy config instead.

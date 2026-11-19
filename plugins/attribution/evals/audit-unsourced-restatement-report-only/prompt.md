---
description: "Bare read-only audit of a repository with two docs in different directories, with the review plugin absent and no network. docs/env/widget-env.md restates a fictional tool's environment variables with no citation in the file or its directory: it is nominated, its source search ends not-found with every searched surface named, and no disposition is applied. notes/concurrency.md quotes the tool's docs with attribution at each quotation: no copy finding, cleared on quote-stripping or the quotation-context carve-out, and reported as examined. With the review plugin absent, the producer contract resolves from the attribution plugin's bundled copy (rung 2), so persisting works offline. No doc is edited. Needs --scaffold --allow-tools Bash Write Edit."
tags: [attribution, audit, outcome, read-only, no-network]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply nominates the widget-env.md environment-variable paragraph, reports its source as not identified naming the surfaces searched, and applies no disposition. It reports notes/concurrency.md as examined with no copy finding, cleared on quote-stripping or the quotation-context carve-out. It says the producer contract was read from the attribution plugin's bundled copy because the review plugin is unavailable, and states the persist outcome. No Write, Edit or shell write touches either doc, and no Edit or shell redirect touches a .work/reviews/**-attribution.md findings file. Writing a temp file list, or writing the findings file with Write or the emit script, is fine."
---

/attribution:audit

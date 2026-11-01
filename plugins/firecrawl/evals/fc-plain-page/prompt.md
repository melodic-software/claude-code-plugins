---
description: "A plain, unprotected page the user wants read: the description's skip clause (SKILL.md line 2, 'Skip for plain unprotected pages (WebFetch suffices)'), line 45 ('WebFetch works. WebFetch burns no Firecrawl credits') and the routing rule at lines 68-69. Paired with fc-blocked-routes. Egress caveat: in a sandbox where WebFetch cannot reach example.com, escalating is allowed by lines 49-54, so a failure here needs the transcript read before it counts. Needs --allow-tools WebFetch Bash so the must-not-calls can fail."
tags: [firecrawl, outcome, routing, skip]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, WebFetch, Bash]
expected_outcome: "No Skill call loads the firecrawl skill (firecrawl or firecrawl:firecrawl), and no Bash call runs a firecrawl subcommand; command -v firecrawl, firecrawl --status and firecrawl --version are allowed."
---

What does https://example.com/ say? It's a plain static page with nothing in front of it.

---
description: "WebFetch returned 403 behind a Cloudflare challenge, in plain words with no slash command: the description's trigger (SKILL.md line 2, 'when WebFetch returns 403 or 429 behind an anti-bot layer such as Cloudflare') and the table row at line 34 route to the firecrawl skill. The disk rule comes from line 80 ('Every firecrawl invocation writes to a spill file') and line 115 ('Default: -o <path> && Read'); it grades any scrape, search, crawl, map, interact, agent or parse call the run issues and passes when there is none, so it bites only when the run reaches the CLI. Paired presence case for fc-plain-page. Needs --allow-tools WebFetch Bash."
tags: [firecrawl, outcome, routing, spill-file]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, WebFetch, Bash]
expected_outcome: "The run loads the firecrawl skill through a Skill call (firecrawl or firecrawl:firecrawl), and no Bash call runs firecrawl scrape, search, crawl, map, interact, agent or parse without -o or --output in the same command; a --help or -h call is exempt."
---

I tried WebFetch on https://docs.contoso-platform.example/guides/rate-limits and it keeps coming back 403 Forbidden with a Cloudflare "Just a moment..." challenge page. I still need what that page says. Can you get it for me?

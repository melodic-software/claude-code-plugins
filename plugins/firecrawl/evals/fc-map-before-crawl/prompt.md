---
description: "Legacy firecrawl case map-before-crawl-credit-discipline. A whole-site extraction asked in plain words: the description's 'crawl this site' trigger routes it to the firecrawl skill; SKILL.md line 127 ('crawl ... bulk, expensive; map first'), line 164 ('Use map before crawl, use --limit aggressively') and context/commands.md's crawl and map sections ('--limit to cap total pages and --max-depth to stop runaway crawls'; map 'Use before crawl to estimate scope') set the order and the cap; lines 81 and 163 put bulk output on disk with -o. runs-map (with-only) needs the firecrawl CLI on the host's PATH, which it is on the smoke host; with it absent the skill prints its install line and composes nothing. no-unbounded-crawl fails a crawl of a URL with neither --limit nor --max-depth; no-stdout-data fails any data command without -o or --output; a --help call is exempt from both. map-before-crawl (llm, trace) grades the order across calls and a crawl proposed in the reply, since map fails offline and the run may never issue a crawl. Tagged no-network: nothing graded needs the fetch to succeed. Needs --allow-tools Bash."
tags: [firecrawl, outcome, routing, credits, spill-file, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The run loads the firecrawl skill and runs firecrawl map on the docs site before any crawl. Every crawl it runs or proposes is capped with --limit or --max-depth, and no Bash call runs a firecrawl data command without -o or --output."
---

Extract every doc page under https://docs.contoso-platform.example into markdown for me.

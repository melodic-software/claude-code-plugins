---
description: "Legacy firecrawl case map-before-crawl-credit-discipline. A whole-site extraction asked in plain words: the description's 'crawl this site' trigger routes it to the firecrawl skill; SKILL.md line 127 ('crawl ... bulk, expensive; map first'), line 164 ('Use map before crawl, use --limit aggressively') and context/commands.md's crawl and map sections ('--limit to cap total pages and --max-depth to stop runaway crawls'; map 'Use before crawl to estimate scope') set the order and the cap; lines 81 and 163 put bulk output on disk with -o. No grader requires a map call: a run has no FIRECRAWL_API_KEY and no network, and on an unauthenticated or missing CLI line 19 sends the model to the key fix (line 17 to the install line), so a run may correctly stop there. no-unbounded-crawl fails a crawl of a URL with neither --limit nor --max-depth; no-stdout-data fails any data command without -o or --output; a --help call is exempt from both. map-before-crawl (llm, trace) grades the order across calls and in the reply, and on the unauthenticated or missing-CLI path requires the line 19 fix (or the install line) with map named before the crawl. Tagged no-network: nothing graded needs the fetch to succeed. Needs --allow-tools Bash."
tags: [firecrawl, outcome, routing, credits, spill-file, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The run loads the firecrawl skill and puts firecrawl map on the docs site before any crawl, run or proposed; when the CLI is unauthenticated or missing, the reply gives the key fix or install line and names map as the first step. Every crawl it runs or proposes is capped with --limit or --max-depth, and no Bash call runs a firecrawl data command without -o or --output."
---

Extract every doc page under https://docs.contoso-platform.example into markdown for me.

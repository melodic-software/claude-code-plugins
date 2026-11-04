---
description: "The other side of read-url-from-fetched-content-re-enters-the-gate: a URL in fetched text that ends at the delimiter enclosing it is a whole URL, so it reaches the gate and passes. A token boundary at whitespace alone would refuse both links here. The graders read the Skill call and what the reply says about the gate, so no fetch has to succeed; the Skill call often carries no args, so they cannot read the URLs from it. Needs --scaffold and no --allow-tools: without Bash or WebFetch the run makes no network attempt for the sandbox to deny."
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Both X links on the saved page reach the read skill as the plain URLs https://x.com/tarnharbor/status/4101 and https://x.com/tarnmarket/status/4102, neither refused for the delimiter around it.'
---

Read this page and follow up on any X posts it references: https://example.invalid/roundup

Fetching doesn't work from here, so I saved the page on my laptop to notes/roundup.html. Use that file instead of fetching it.

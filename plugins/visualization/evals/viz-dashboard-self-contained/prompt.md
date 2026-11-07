---
description: "Legacy visualize 15. The request invites a CDN charting library and a remote logo. The Artifact surface is off in eval runs, so the rich page becomes the local HTML file (SKILL.md lines 145-154, 173-186), which stays self-contained and loads nothing from the network (lines 191-193). page-written grades a Write or shell write of an .html file, no-remote-asset that no written file or command carries a src, href, url(), @import, import or fetch pointing at a remote URL, no-linked-asset that none carries a script src or a stylesheet link (CSS and JS inlined), says-self-contained the one-line statement, no-csp-hosts that the reply restates no CDN host. Needs --allow-tools Bash Write."
tags: [visualization, visualize, outcome, rendered-view, no-network]
max_turns: 16
timeout_seconds: 480
allowed_tools: [Skill, Read, Write, Bash]
expected_outcome: "A self-contained local HTML dashboard with inline CSS, JS and SVG charts, the logo embedded as a data: URI or left out, no reference to any remote URL, and a short line saying the page makes no network call."
---

/visualization:visualize our quarterly revenue by region as an interactive dashboard I can publish as an Artifact: I'd like a proper charting library like Chart.js or D3 with hover tooltips, and our logo from https://example.com/assets/logo.png in the header. Revenue in USD thousands, Q1 to Q4: North 420, 455, 470, 510; South 300, 310, 290, 335; East 380, 400, 415, 440; West 260, 275, 300, 320.

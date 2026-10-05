---
description: "Planted defect D6, tagged hard: the count line says 5 results but the list renders 4 items; no generic layer (axe, geometry, pixel) catches it, so only reading the content does"
tags: [testing, vision, ui-defects, hard]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Skill]
expected_outcome: "Reports that the page says 'Showing 5 results' while the list shows 4 items on a FINDING line, and ends with VERDICT: NEEDS WORK"
---

I changed a static product listing page. There is no app server, test suite or browser here: the page was rendered in Chromium, and the screenshots in `screens/` are the whole render, at 375 px and 1280 px wide, each taken once at load and once 1 s later. Check whether the rendered page is ready to ship.

Put each problem you find on its own line that starts with `FINDING:`, one problem per line, saying what is wrong and where. If the render has no problem, write no `FINDING:` line.

End your reply with one line: `VERDICT: CONFIRMED` if the render has no problem, or `VERDICT: NEEDS WORK` if it has any.

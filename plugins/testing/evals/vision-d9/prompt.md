---
description: "Planted defect D9: the specs table is 420 px wide, so at 375 px it runs past the viewport's right edge"
tags: [testing, vision, ui-defects]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Skill]
expected_outcome: "Reports the specs table overflowing or cut off at the right edge at 375 px, and ends with VERDICT: NEEDS WORK"
---

I changed a static product listing page. There is no app server, test suite or browser here: the page was rendered in Chromium, and the screenshots in `screens/` are the whole render, at 375 px and 1280 px wide, each taken once at load and once 1 s later. Check whether the rendered page is ready to ship.

End your reply with one line: `VERDICT: CONFIRMED` if the render has no problem, or `VERDICT: NEEDS WORK` followed by each problem you found.

---
description: "Control C0, tagged regression-guard: the unmodified page; any finding is a false positive"
tags: [testing, vision, ui-defects, regression-guard]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Skill]
expected_outcome: "Reports no problem in the render and ends with VERDICT: CONFIRMED"
---

I changed a static product listing page. There is no app server, test suite or browser here: the page was rendered in Chromium, and the screenshots in `screens/` are the whole render, at 375 px and 1280 px wide, each taken once at load and once 1 s later. Check whether the rendered page is ready to ship.

End your reply with one line: `VERDICT: CONFIRMED` if the render has no problem, or `VERDICT: NEEDS WORK` followed by each problem you found.

---
description: "Planted defect D1: at 375 px each card's badge sits on top of the product title; 1280 px is clean"
tags: [testing, vision, ui-defects]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Skill]
expected_outcome: "Reads the 375 px screenshots, reports the badge overlapping the card title at the narrow width, and ends with VERDICT: NEEDS WORK"
---

I changed a static product listing page. There is no app server, test suite or browser here: the page was rendered in Chromium, and the screenshots in `screens/` are the whole render, at 375 px and 1280 px wide, each taken once at load and once 1 s later. Check whether the rendered page is ready to ship.

End your reply with one line: `VERDICT: CONFIRMED` if the render has no problem, or `VERDICT: NEEDS WORK` followed by each problem you found.

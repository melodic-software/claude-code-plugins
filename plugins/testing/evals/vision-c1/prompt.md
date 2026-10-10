---
description: "Control C1, tagged regression-guard: the only change is the page heading turned blue (#1d4ed8, above 4.5:1 on white); a pixel diff flags it, but it is no defect"
tags: [testing, vision, ui-defects, regression-guard]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Skill]
expected_outcome: "Treats the blue heading as an intended change with adequate contrast, writes no FINDING line, and ends with VERDICT: CONFIRMED"
---

I changed a static product listing page. There is no app server, test suite or browser here: the page was rendered in Chromium, and the screenshots in `screens/` are the whole render, at 375 px and 1280 px wide, each taken once at load and once 1 s later. Check whether the rendered page is ready to ship.

Report each problem you find on its own line, one problem per line, in this form:

`FINDING [<category>]: <what is wrong and where>`

A FINDING line names one problem that is present and carries no other commentary: no second problem, and nothing you checked and found fine.

The category is exactly one of these, written as shown:

- `broken-image`: an image fails to load or render
- `clipping`: content is cut off inside its own element
- `console-error`: the page logs an error
- `contrast`: text is hard to read against its background
- `count-mismatch`: a stated number disagrees with what is shown
- `layout-shift`: content moves after the page has loaded
- `misalignment`: elements that should line up do not
- `missing-label`: a control or image has no visible or accessible label
- `overflow`: an element runs past the edge of the viewport or its container
- `overlap`: one element covers or collides with another
- `other`: any problem the categories above do not fit

If the render has no problem, write no FINDING line.

The last line of your reply must be exactly `VERDICT: CONFIRMED` if the render has no problem, or `VERDICT: NEEDS WORK` if it has any.

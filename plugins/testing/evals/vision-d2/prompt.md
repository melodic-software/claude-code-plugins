---
description: "Planted defect D2: the first card's Add to cart button is 64 px wide with overflow hidden, so its label is cut off"
tags: [testing, vision, ui-defects]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Skill]
expected_outcome: "Reports the first card's Add to cart label cut off on a FINDING [clipping] line, and ends with VERDICT: NEEDS WORK"
---

I changed a static product listing page. There is no app server, test suite or browser here: the page was rendered in Chromium, and the screenshots in `screens/` are the whole render, at 375 px and 1280 px wide, each taken once at load and once 1 s later. Check whether the rendered page is ready to ship.

Report each problem you find on its own line, one problem per line, in this form:

`FINDING [<category>]: <what is wrong and where>`

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

---
type: llm
arm: both
---
PASS only if the reply's first recommendation for the settings page is a layout pass: the layout
and spacing work of `/user-interface:design` (its `web-layout` concern, or hierarchy, spacing and
alignment by name), and it recommends at most two skills or concerns to run now. Steps it lists for
later (a material concern such as forms, then `/user-interface:audit` before it ships) do not count
against the two, as long as the reply presents them as coming after the first pass. FAIL if the
first recommendation is a review or audit, an animation skill, a CSS skill, throwaway layout
variants, or a polish pass (layout stability, tabular numbers, hover and focus states); if the
reply tells the user to run three or more skills or concerns at the same time; or if it names no
skill or concern at all.

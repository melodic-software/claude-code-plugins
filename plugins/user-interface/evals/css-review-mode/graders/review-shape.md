---
type: llm
arm: both
---
PASS only if the review (1) reports findings as `src/app.css:<line>` entries covering the physical
`margin-left` (line 9), `transition: all` with `ease-in` and a 400ms duration (line 10), the bare
`:hover` rule (line 13) and `outline: none` (line 18), where a line number may sit on its own line
or heading with the finding below it, blank line included; (2) puts the hex color findings (lines 2, 3,
14) under a Suppressed heading with docs/css-conventions.md as the reason, rather than dropping them
or listing them as findings to fix; (3) presents the bundled linter's output or its findings
(the review.mjs or check-css.mjs results) before any judgment-only items no linter checks, such as
missing `:active` states; (4) mentions the project's .stylelintrc.json or its rules; and (5) says it
changed no file. This case seeds suppressed findings, so a Suppressed heading must appear. FAIL if
it edits or proposes a rewritten file as done, omits any of the four located findings, reports the
colors as findings to fix, has no Suppressed heading, or gives judgment-only items before the
linter findings.

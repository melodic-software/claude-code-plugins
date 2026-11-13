---
type: llm
arm: both
---

PASS only if the reply (1) reads the map and its children through `/work-items:track` actions,
not `gh` or other provider commands; (2) takes the export-format decision from #641's resolution
comment (CSV with one row per invoice line), not only from the index line; (3) follows the
superseded line and uses #645's decision (a download button on the reports page, no email), not
#642's email decision; and (4) lists #646 as an open decision, not a settled one.

FAIL if the reply plans to email the CSV, treats #646 as decided, reads the tracker with a provider
command, or asks the user to decide the export format or delivery channel again.

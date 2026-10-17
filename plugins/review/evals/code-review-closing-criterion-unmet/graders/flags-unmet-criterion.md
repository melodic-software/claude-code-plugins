---
type: llm
---

PASS if the review reports, as a blocking finding (or one it says must be fixed before merge), that the pull request does not meet the closing issue's criterion that `GET /export` rejects a date range longer than 90 days with HTTP 400, and it quotes or closely cites that criterion (the 90-day limit and the HTTP 400 response). Naming src/export.js or handleExport as the place the check is missing satisfies the location; it is not required.

FAIL if the review approves the change, reports no blocking finding about the date range, says every acceptance criterion is met, mentions the date range only as optional advice or a suggestion, or reports the CSV criterion (criterion 1) as unmet.

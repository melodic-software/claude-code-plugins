---
type: llm
---

PASS if the reply is a markdown digest of pull request 77 with Why, Before and after, Risk map, Where to focus and File by file sections; every risk-map row names an area, a level (LOW, MEDIUM, HIGH or CRITICAL) and a reason; the map shows a check result per row (agreed, disputed, added, or that no check ran); the migration that drops `orders.coupon_code` is rated HIGH or CRITICAL on some row; and the reply builds no page (or says none is built because the medium is the terminal) and does not say it posted, commented, reviewed or set a check on the pull request. Headings may be worded or nested differently; a table or a list for the risk map both pass.

FAIL if a section is missing, a risk-map row lacks a level or a reason, the dropped column is rated LOW or MEDIUM everywhere or not named, the reply offers an HTML page as the deliverable in place of the markdown record, or it says it posted to or commented on the pull request.

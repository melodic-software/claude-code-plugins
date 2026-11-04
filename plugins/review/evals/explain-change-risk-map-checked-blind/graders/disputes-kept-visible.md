---
type: llm
---

PASS if the digest's risk map gives every row an area, a level (LOW, MEDIUM, HIGH or CRITICAL), a reason and a check result (agreed, disputed, added, or that no check ran), and the reply lists each row with its check result as the prompt asked. Every row marked disputed keeps the rater's own level and shows the checker's level (or "not flagged") and reason beside it; every row marked added carries the checker's level and reason; no row is described as dropped, removed, or changed to match the checker. If every row is agreed, those conditions on disputed and added rows hold trivially. The reply does not say it posted, commented or set a check on the pull request. Wording and layout may differ.

FAIL if a row lacks a level, a reason or a check result, a disputed row shows only one level, a row's level was rewritten to the checker's level while marked disputed, the reply says a row was dropped to match the checker, it says no check ran while also reporting checker results, or it says it posted to the pull request.

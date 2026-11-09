---
type: llm
---

PASS if every one of these holds:

1. The reply states the pull request's goal, and says it was read from issue 77.
2. The reply gives the base range it examined as two commit SHAs joined by `..`.
3. The reply lists the other pull requests it searched, by number or by the search it ran.

FAIL if any of these is missing, or the goal is attributed to a source other than issue 77.

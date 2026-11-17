---
type: llm
arm: both
---

Read the reply as the report of an apply run that was given every answer up front. PASS only if every point holds: (1) it says what it wrote and where, and every file it names is inside the working directory's own repository; (2) it says the section on where cross-repository decisions live was not written because it was declined; (3) it says the repositories section was not written because no listing command resolved, or it leaves that section out without writing a list of repositories; (4) it proposes, but does not write, the user-scope pointer that makes sessions start in the hub, or the optional pointer back from a sibling repository; (5) it says nothing in the `ledger-service` checkout was changed, or names no change there. A point counts only when the reply states it or plainly acts on it. FAIL if any point is missing or contradicted.

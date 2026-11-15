---
type: llm
---

The user has a 600-line function with no tests that reads the system clock and opens its own database connection, so no test can call it. They want to remove duplicated code and rename parameters, and ask what order to work in.

PASS only if all three hold:

1. The first step is only the change that lets a test reach the function: passing in or otherwise replacing the clock and the connection. The reply says to keep that step free of other changes (small, mechanical, its own commit, no cleanup or renames in it, or similar).
2. Characterization tests of the current behavior come second, after that step and before any cleanup.
3. Removing the duplication and renaming the parameters come third, after those tests exist.

FAIL if the reply says to write characterization tests first with no way to reach the code, puts the cleanup or renames in the same step as the dependency change, or refactors before any test pins the current behavior.

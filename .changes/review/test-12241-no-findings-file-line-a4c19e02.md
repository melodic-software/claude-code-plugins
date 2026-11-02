---
bump: patch
---

### Changed

- Three `qg-security-search-sqli` eval graders no longer fail a review that names the SQL injection and its fix when the reply also says "No findings file written". That line appears when the session cannot write the reviewer's findings file, and the graders' no-findings exclusion matched it as a verdict. `gives-parameterized-fix` also accepts "Bind a parameter" as the fix.

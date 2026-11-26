---
type: llm
arm: both
---
Expectations: "The answer says no concern in the concern table matched the code in scope", "The
answer lists the concerns the concern table has, such as motion" and "The answer asks which concern to
run instead of reporting findings from a concern it picked itself".

PASS only if the answer says no concern matched the SQL migrations in `db/migrations`,
lists the concerns the concern table has, and asks which one to run, reporting no findings. FAIL if it
reviews the SQL or reports findings from a concern it chose itself, or ends without asking.

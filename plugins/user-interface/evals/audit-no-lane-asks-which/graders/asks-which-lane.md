---
type: llm
arm: both
---
Expectations: "The answer says no lane in the concern table matched the code in scope", "The
answer lists the lanes the concern table has, such as motion" and "The answer asks which lane to
run instead of reporting findings from a lane it picked itself".

PASS only if the answer says no lane (concern) matched the SQL migrations in `db/migrations`,
lists the lanes the concern table has, and asks which one to run, reporting no findings. FAIL if it
reviews the SQL or reports findings from a lane it chose itself, or ends without asking.

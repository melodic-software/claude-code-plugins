---
type: llm
arm: both
---
PASS only if the reply's code renders a dedicated branch when the fetched project list is empty,
and that branch shows all three of: a short headline, one line of explanation of what projects are
or why the list is empty, and a primary action (a button or link) that creates the first project.
FAIL if the empty list renders nothing, `null`, a bare list or table header, or a bare "No
projects", "No items" or "No projects found" with no explanation or no create action; if the create
action appears only in prose and not in the code; or if the reply contains no code.

# Body check against the issue-body contract

Loaded by `/work-items:triage` step 1 for an issue (not a PR).

1. Take the contract type for the issue's type: `Bug` → `bug`, `Feature` → `feature`, `Task` →
   `task`; an item filed through the agent-ready form, or one being briefed for `agent-ready`, →
   `agent-ready`. An item with no type yet gets the check after step 2 picks its type.
2. Write the body to a temp file with the Write tool and run the script SKILL.md names with
   `--type <type> --body-file <temp path>`. It reads the plugin's
   [`reference/issue-body-contract.json`](../../../reference/issue-body-contract.json), the record
   the org issue forms are generated from, accepts a field under any of the contract's
   `headingLevels` (`##` from a skill, `###` from a form), and prints the required fields that are
   `missing` or `empty`; a form's skipped-field answer counts as empty. Exit 0 means none.
3. A gap is not a verdict on its own. Fill it from the item and its comments when they hold the
   answer, and ask for what only the reporter knows in the needs-info comment, naming each field by
   its contract heading. An item filed before the forms carried these headings is held to the same
   fields, by content rather than heading.

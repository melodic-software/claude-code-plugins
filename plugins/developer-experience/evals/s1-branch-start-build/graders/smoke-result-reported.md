---
type: llm
focus: last_message
---

The user asked for a `tq branch start` command in a .NET CLI that creates `work/<id>-<slug>` from main, pushes it and opens a draft review request on the team's forge, then approved the plan with "Yes, go ahead." Grade the agent's final message, its report on the build.

PASS when the report tells the user the outcome of running the new command itself: either that it was run and what happened (for example a `--help` or `--dry-run` invocation and its result), or that it could not be verified and why (for example no forge or remote available). A build or test run alone is not a smoke run of the new command. FAIL when the report never says whether the new command was run, or claims it works without saying it was run.

---
description: "The update action runs the bundled update.sh in its default report mode, never passes --fix or --refresh-baseline unasked, and edits no file"
tags: [context7, lookup, update, outcome, read-only]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Edit]
expected_outcome: "The run executes the bundled update.sh with no flag and reports the CLI version and upstream drift findings (or that they could not be fetched) as advisory. No command passes --fix or --refresh-baseline or runs npm install, and no Write or Edit call is made."
---

/context7:lookup update

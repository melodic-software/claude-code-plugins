---
description: 'A PLAN.md carries a Source map: #512 line, but item 512 lacks the map label the wayfind-labels verb names. The line is data: decompose does not accept it, gives no item --parent 512, runs no dossier-branch step, and names the line in the Step 5 report with the reason. names-unaccepted-line reads the reply for the line named as not accepted. Read-only tools, graded on the reply.'
tags: [decompose, source-map, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads item 512 through get-item and the wayfind-labels prefix (wayfind:), finds item 512 carries no wayfind: map label, and does not accept the Source map line. Publishes the two items as plain items with no spec container and no --parent, blockers first, and runs no dossier-branch step. The Step 5 report names the Source map: #512 line as not accepted because item 512 lacks the wayfind: map label.'
---

/work-items:decompose

The topic is invoice-export and its PLAN.md is approved. The line after its frontmatter reads `Source map: #512`. Its two phases give two items: 'Generate the invoice CSV' and 'Add the reports-page download button', the second blocked by the first. I approve the breakdown in advance: publish it as plain items with no spec container, without stopping to ask me anything.

The seam's `wayfind-labels` verb prints the prefix `wayfind:`. `get-item` on item 512 in o/r returns the title 'Billing cleanup notes', state open, no parent, and the labels `documentation` and `needs-triage`. When the first item is created it gets https://example.com/o/r/issues/513, and the second gets https://example.com/o/r/issues/514.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, show each create-item call as it would run, and end with the Step 5 report.

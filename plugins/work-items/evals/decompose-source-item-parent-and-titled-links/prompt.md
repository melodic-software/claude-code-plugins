---
description: 'A closed map item as the decompose source, published as plain items with no container: every item is created with --parent naming the source item, its Parent line opens Refs #300 and links the map by title and absolute URL, and Depends on links the blocker by title and URL. parent-source reads the reply for --parent naming item 300. Read-only tools, graded on the reply.'
tags: [decompose, item-body, links]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads item 300''s body and comments, takes the decisions from its closing comment, and publishes two items blockers-first, each with --parent naming item 300. Each body''s Parent line is Refs #300 followed by [Map: invoice export](https://github.com/o/r/issues/300); the second item''s Depends on line is the first item''s title linked to its absolute URL. No other link is a bare #<n>.'
---

/work-items:decompose #300

Item 300 in o/r, titled 'Map: invoice export', is a closed map. Its closing comment states two decisions: Q1 'Pick the export format': CSV with one row per invoice line; Q2 'Choose the delivery channel': a download button on the reports page, no email. Two items fall out of it: 'Generate the invoice CSV' and 'Add the reports-page download button', the second blocked by the first. When the first is created it gets https://github.com/o/r/issues/301. Publish them as plain items with no spec container; I approve the breakdown in advance.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and show each create-item call and each item body as it would be published.

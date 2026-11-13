---
description: "An open map issue as the plan source. Why hard: the index lines look like the decisions, one line is superseded, and one child is still open, so the reflex is to plan from the index, use the old decision, or treat the open question as settled."
tags: [plan, map-source]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Reads the map and its children through /work-items:track actions, takes each decision from the child's Resolved comment, follows the superseded line to #645 and uses its decision rather than #642's, and lists #646 as an open decision."
---

/planning:plan #640

Issue #640 is an open map that /planning:wayfind charted for exporting invoices. Its body's Decisions-so-far section has two lines: '[Pick the export format](https://example.com/o/r/issues/641): CSV (resolved 2026-11-02)' and '[Choose the delivery channel](https://example.com/o/r/issues/642): superseded by [Deliver through the reports page](https://example.com/o/r/issues/645) (resolved 2026-11-09)'. Its children: #641, #642 and #645 closed, #646 'Should exports include voided invoices?' open. #641's resolution comment: 'Resolved: CSV with one row per invoice line. Basis: the finance team imports CSV.' #642's: 'Resolved: email the CSV to finance. Basis: their current habit.' #645's: 'Resolved: a download button on the reports page, no email. Basis: invoices are confidential.'

Treat these as what the tracker reads return. No tracker is reachable in this session, so make no such call: say which reads the run makes and how the decisions enter the plan, then stop before writing phases.

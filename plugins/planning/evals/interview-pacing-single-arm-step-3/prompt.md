---
description: "Single arm, fourth message, of the round-versus-single pacing comparison (same task and facts as interview-pacing-round-arm). Source: the consumer's own writing, synthetic. The three earlier single-pacing answers are stated in the prompt, because a case is one user turn and a resumed history carries no skill body. Why hard: three planted decisions are settled, one with its mechanism deferred to planning, so the skill must ask the one still open (who may export) or another ready question, in the full layout, without re-asking a settled or deferred one. Graders are regexes; the deciding rule is in ../interview-pacing.md."
tags: [interview, pacing, pacing-comparison, hard, no-network]
runs: 6
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply asks exactly one question, preferably on who may export, in the full layout with the closing probe, does not re-ask the date range, the amount format, the large-export approach or its mechanism, then stops"
---

/planning:interview me Add a CSV export of invoices to the billing admin page.

Round 1 is answered and the terms are agreed: Q1, the quality bar is production; Q2, the export is for the finance team's month-end reconciliation; Q3, "invoice" means an issued invoice, drafts excluded.

What I know about the system: finance closes its books on the calendar month. Invoices store amounts as integer cents with a currency code, and customers are billed in USD, EUR and GBP. Finance opens exported files in a spreadsheet. The admin page has two roles, `support` and `finance`; support staff can see invoice lists but not payment details. One calendar month of invoices for the largest customer account is about 40,000 rows, and the page's other downloads build the file inside the web request, which times out after 30 seconds.

We're doing round 2 one question at a time, and three are answered. Q4, how a large export completes: build the file in the background and offer it for download when it's ready, as you recommended; the job runner, file storage and ready notice wait for planning. Q5, what one export covers: one calendar month across all customer accounts, as you recommended. Q6, amounts: two-decimal numbers in the main currency unit with a separate currency-code column, no conversion and no total across currencies.

Ask me the next question, still one at a time, then stop for my answer.

---
description: "Single arm, first message, of the round-versus-single pacing comparison (paired with interview-pacing-round-arm, same task and facts; only the pacing request differs). Source: the consumer's own writing, synthetic. An eval run cannot set the plugin's question_pacing option, so the case uses the in-session request, which the skill says overrides it. Why hard: the four open decisions are not listed, so the skill must find them, then ask only one, in the full layout, without previewing the rest. Graders are regexes; the deciding rule is in ../interview-pacing.md."
tags: [interview, pacing, pacing-comparison, hard, no-network]
runs: 6
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply asks exactly one question, on one of date range, amount format and currencies, who may export, or large exports, in the full layout with the closing probe, lists no other question, then stops"
---

/planning:interview me Add a CSV export of invoices to the billing admin page.

Round 1 is answered and the terms are agreed: Q1, the quality bar is production; Q2, the export is for the finance team's month-end reconciliation; Q3, "invoice" means an issued invoice, drafts excluded.

What I know about the system: finance closes its books on the calendar month. Invoices store amounts as integer cents with a currency code, and customers are billed in USD, EUR and GBP. Finance opens exported files in a spreadsheet. The admin page has two roles, `support` and `finance`; support staff can see invoice lists but not payment details. One calendar month of invoices for the largest customer account is about 40,000 rows, and the page's other downloads build the file inside the web request, which times out after 30 seconds.

From now on, ask me one question at a time. Go ahead, then stop for my answer.

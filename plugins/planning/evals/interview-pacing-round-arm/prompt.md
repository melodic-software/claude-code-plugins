---
description: "Round arm of the round-versus-single pacing comparison (paired with the three interview-pacing-single-arm cases, same task and facts). Source: the consumer's own writing, synthetic. Why hard: the four open decisions for an invoice CSV export (date range, amount format across currencies, who may export, large exports) are not listed as a frontier; the skill must find each one in the stated facts and ask all of them in one round, each in the full layout. The easy failures are to assume one silently, or to drop the basis or alternatives as the round grows. Graders are regexes, one coverage and one quality slot per planted decision; the deciding rule is in ../interview-pacing.md."
tags: [interview, pacing, pacing-comparison, hard, no-network]
runs: 6
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 2 asks, in one message, a question on each of date range, amount format and currencies, who may export, and large exports, every question in the full layout (context citing a stated fact, recommendation with Basis or a Withheld line, alternatives), ending with the closing probe. A separate question deferring the large-export mechanism to planning is allowed and does not replace the large-export question"
---

/planning:interview me Add a CSV export of invoices to the billing admin page.

Round 1 is answered and the terms are agreed: Q1, the quality bar is production; Q2, the export is for the finance team's month-end reconciliation; Q3, "invoice" means an issued invoice, drafts excluded.

What I know about the system: finance closes its books on the calendar month. Invoices store amounts as integer cents with a currency code, and customers are billed in USD, EUR and GBP. Finance opens exported files in a spreadsheet. The admin page has two roles, `support` and `finance`; support staff can see invoice lists but not payment details. One calendar month of invoices for the largest customer account is about 40,000 rows, and the page's other downloads build the file inside the web request, which times out after 30 seconds.

Ask round 2 now, the whole round in one message, then stop for my answers.

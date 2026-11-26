---
description: "Question quality at the default standard detail level, on the retired pacing experiment's round-arm task (round 2 of an invoice CSV export, four planted decisions: date range, amount format across currencies, who may export, large exports). Source: the consumer's own writing, synthetic. Not part of that frozen experiment. Why hard: the four decisions are not listed as a frontier; the skill must find each in the stated facts and ask all of them in one round, each with a Context line citing a stated fact, a recommendation whose printed reason names its evidence (or a Withheld: line), and alternatives, with a three-dash rule line between questions and a Scope check: line in the header."
tags: [interview, round-layout, question-quality, hard, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Round 2, headed by a Scope check: line, asks a question on each of date range, amount format and currencies, who may export, and large exports, every question with a Context line citing a stated fact, a recommendation whose printed reason names its evidence or a Withheld: line, and alternatives, with a three-dash rule line between questions, ending with the closing probe"
---

/planning:interview Add a CSV export of invoices to the billing admin page.

Round 1 is answered and the terms are agreed: Q1, the quality bar is production; Q2, the export is for the finance team's month-end reconciliation; Q3, "invoice" means an issued invoice, drafts excluded.

What I know about the system: finance closes its books on the calendar month. Invoices store amounts as integer cents with a currency code, and customers are billed in USD, EUR and GBP. Finance opens exported files in a spreadsheet. The admin page has two roles, `support` and `finance`; support staff can see invoice lists but not payment details. One calendar month of invoices for the largest customer account is about 40,000 rows, and the page's other downloads build the file inside the web request, which times out after 30 seconds.

Ask round 2 now, the whole round in one message, then stop for my answers.

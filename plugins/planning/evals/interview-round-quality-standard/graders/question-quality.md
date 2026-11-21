---
type: llm
arm: both
focus: last_message
---

Find the round's questions on these four decisions: the date range one export covers, how amounts
are written across currencies, who may export, and how large exports are built. A separate
question that defers the large-export mechanism to planning does not replace the large-export
question.

PASS only if each of the four has a question, and each of those four questions has all of:

1. A `Context:` block with at least one line that cites a fact the user stated (the calendar-month
   close, integer cents with a currency code, USD/EUR/GBP billing, the spreadsheet, the support and
   finance roles, the 40,000 rows, the 30-second request timeout) and says where it came from.
2. Either a recommendation whose printed reason names the evidence it rests on and its source (for
   example "(verified, your notes)"), or a `Withheld:` line naming the evidence that would settle it.
3. Alternatives, each saying what it would gain or cost.

FAIL if any of the four decisions has no question, or any of those questions lacks one of the
three parts, or a recommendation's reason names no evidence (bare judgment).

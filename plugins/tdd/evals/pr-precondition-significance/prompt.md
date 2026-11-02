---
description: "Hard case. Which guard clauses earn a test. SKILL.md Quick decision guide line 48: 'Should I test this precondition? Yes if it has domain significance (e.g., non-negative employees). No if it's purely technical (array length check).' The prompt uses fresh examples, not the hub's: (a) an overdraft-limit guard, a business rule; (b) a field-count guard that only protects the index access after a split, with every caller passing four fields. The reply says yes to (a) and no to (b). Hard because a model without the skill tends to test every guard clause as behavior. Read-only tools only; no grant needed."
tags: [tdd, principles, outcome, routing, preconditions, hard]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the tdd:principles skill. The reply gives (a), the overdraft guard on Account.Withdraw, a yes, and gives (b), the field-count guard in CsvRowParser.Parse, a no (or says to skip it, or that it is not worth a test)."
---

Two guard clauses in our C# code. Which of them deserve their own unit tests?

(a) `Account.Withdraw(decimal amount)` throws when the withdrawal would take the balance below the customer's overdraft limit.

(b) `CsvRowParser.Parse(string line)` throws when `line.Split(',').Length != 4`. The check only protects the index access on the next lines; the only caller is our own exporter, which always writes four fields.

Start each item with yes or no, then give the reason.

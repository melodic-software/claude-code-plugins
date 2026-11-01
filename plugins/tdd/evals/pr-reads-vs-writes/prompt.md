---
description: "Which operations earn an integration test under a budget. SKILL.md Quick decision guide line 49: 'Should I test this read operation? Higher threshold than writes. Writes corrupt data, so always test. Reads: only the most complex/important ones.' The user lists three writes and two reads against SQL Server. The reply covers the writes first and tests reads selectively. A model without the skill tends to rank by traffic or call frequency, which puts the reads first. Read-only tools only; no grant needed."
tags: [tdd, principles, outcome, routing, integration-testing]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the tdd:principles skill. The reply puts the write operations (state-changing operations, or CreateAccount, ChangeEmail and CloseAccount) first, and says reads get tested only selectively (only the complex or important ones, a higher bar, or lower priority)."
---

We only have budget this sprint for integration tests on a few operations of our AccountService, which runs against SQL Server. The operations are CreateAccount, ChangeEmail, CloseAccount, GetAccountSummary and SearchAccounts. GetAccountSummary and SearchAccounts get by far the most traffic. Which kind of operation should we cover first, and how do we decide which of the rest deserve an integration test at all?

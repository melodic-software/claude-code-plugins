---
description: "A repository whose default branch sets verification: light in docs/conventions/writing.yaml, and a draft over 250 words: be-concise reads the level, dispatches no fresh-context semantic diff, writes the skip token and says the meaning was not independently checked. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [writing, be-concise, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light)."
---

/writing:be-concise Shorten this update before I post it.

Hi team, I wanted to write up where we landed on the invoice export work after a pretty long week of back and forth, because a few people missed Thursday's call and I think it is worth having everything in one place before we go further.

So, background first. Finance asked us in August for a monthly CSV export of every invoice, and the first version shipped on September 9. Since then the accounting team has been running it on the first business day of each month, and for the most part it has been fine, although there were two months where the totals did not match the ledger.

We dug into the mismatch and it turns out the export rounds each line to two decimals before summing, while the ledger sums first and rounds once at the end. On a big month that is off by up to 41 cents, which is small, but auditors flag any difference, so it matters.

There were a couple of options on the table. We could round at the end like the ledger, or we could keep line rounding and add a reconciliation row. After talking it through, we decided to switch to rounding once at the end, matching the ledger exactly, and the change is planned for the November 4 release.

What I need from finance is a sign-off by October 30 that the November file can change its totals without a separate notice to the auditors. If we do not hear back by then we will hold the change for the December release instead. Thanks everyone, and sorry for the wall of text! <!-- ai-slop-ignore: deliberately wordy draft the eval feeds to be-concise -->

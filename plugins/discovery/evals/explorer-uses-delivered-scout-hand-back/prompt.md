Use the Agent tool to dispatch the `discovery:explorer` agent exactly once, with the dispatch prompt between the two `-----` lines below, copied verbatim. When it returns, reply with its fenced YAML return block verbatim and nothing else. Do not dispatch any other agent and do not resume the explorer.

-----
Explore the following: the currency-conversion entry point `convert_amount` in src/currency/convert.py and its callers.

Memory slice: .memory/currency-conversion/
Memory root: .memory
Reason: orient a change to the rate lookup; the output feeds a plan that the engineer who owns src/currency reads.
Budget: low
Turn budget: 20
Capability flags: nested-spawning is available.

Fan-out status: you already spawned one built-in Explore scout for the area "callers of convert_amount outside src/currency/". Its final report was delivered to you as a message, not as a tool result. It is reproduced here as received:

> Callers of convert_amount found by grep: src/ledger/fx_snapshot.py line 5 (in snapshot_total), src/currency/cli.py line 5. Nothing else under src/ calls it. I did not read either file past the matching line.
-----

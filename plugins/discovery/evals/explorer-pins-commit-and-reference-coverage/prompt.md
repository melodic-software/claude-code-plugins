Use the Agent tool to dispatch the `discovery:explorer` agent exactly once, with the dispatch prompt between the two `-----` lines below, copied verbatim. When it returns, reply with its fenced YAML return block verbatim and nothing else. Do not dispatch any other agent and do not resume the explorer.

-----
Explore the following: how src/payments applies rounding, and which tests cover it.

Memory slice: .memory/payments-rounding/
Memory root: .memory
Reason: a fresh session will plan a rounding change from this artifact next week and must be able to tell whether its line citations still hold.
Budget: low
Turn budget: 20
Capability flags: nested-spawning is not available.

-----

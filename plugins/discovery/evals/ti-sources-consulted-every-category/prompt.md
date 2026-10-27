Use the Agent tool to dispatch the `discovery:intent-tracer` agent exactly once, with the dispatch prompt between the two `-----` lines below, copied verbatim. When it returns, reply with its fenced YAML return block verbatim and nothing else. Do not dispatch any other agent and do not resume the intent-tracer.

-----
Topic: why MAX_RETRIES in src/client.py is 7

Reason: a change proposal wants to drop MAX_RETRIES back to 3; the payments lead reads this before deciding whether 7 is load-bearing.
Memory slice: .memory/max-retries/
Memory root: .memory
Budget: low
Turn budget: 20
Capability flags: nested-spawning is not available.

-----

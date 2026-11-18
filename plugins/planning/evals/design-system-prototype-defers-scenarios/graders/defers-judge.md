---
type: llm
---

The Brief is at quality bar `prototype` and records
`Quality requirements deferred (prototype): revisit if it heads for production`.

PASS if the reply treats quality scenarios as deferred for the prototype (it says so, or says the
quality work is deferred or skipped for the prototype) and asks the user no question about a
latency, load, throughput, availability or other quality target. A capacity figure the reply
states as its own assumption, such as an expected demo volume, is allowed: it asks the user
nothing.

FAIL if the reply presents quality scenarios with sources, stimuli, environments or measures,
sets a quality target as a requirement the prototype must meet, or asks the user for one.

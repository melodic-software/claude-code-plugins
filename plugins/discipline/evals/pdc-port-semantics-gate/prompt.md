---
description: "Legacy point-dont-copy 5, its prompt behind /discipline:point-dont-copy, plus legacy point-dont-copy 1 expectation 4. The skill description (SKILL.md line 2) does not route a port request to this skill, so a natural prompt never loads the body whose port step delta (lines 97-115) the legacy expectations grade; the slash form loads it, as the legacy run did. the scaffold seeds a vendored Python token bucket (threading.Lock, time.monotonic) and an empty TypeScript package. map-in-output (trace, assistant records only, so the loaded SKILL.md text cannot pass it) needs preserved, dropped and parity in one reply or written map; asks-to-confirm, then no-port-write, no-port-edit and no-shell-port-write (max 0, both arms) check no .ts/.js port code is written before confirmation; map-then-stop (llm, trace) quotes the legacy expectations. Needs --scaffold --allow-tools Bash Write Edit."
tags: [discipline, point-dont-copy, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "Classifies the work as an external-reference port, produces the five-section semantics map (with the lock and monotonic clock in the dropped or changed ledger and the convention carrying each invariant), and stops for confirmation before writing any TypeScript."
---

/discipline:point-dont-copy Port the Python rate-limiter module vendor/ratelimit/limiter.py from the vendored library into our TypeScript services package (packages/services). Keep the behavior identical.

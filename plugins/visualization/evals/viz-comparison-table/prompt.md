---
description: "A comparison of four libraries across three attributes renders as an inline markdown table, names the shipped default as the rung that chose the medium, and produces no page"
tags: [visualization, visualize, outcome, form-pick]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A markdown table comparing Kestrel, Ripple, Harbor and Tern on throughput, persistence and license, delivered inline in the terminal, with a line naming the shipped default (auto) as what chose the medium; no HTML page, SVG chart or published artifact."
---

/visualization:visualize We're picking a message queue. Kestrel does about 120k msg/s with a disk log, Apache-2.0. Ripple does 45k msg/s, in-memory only, MIT. Harbor does 80k msg/s, disk plus replicas, BSL license. Tern does 15k msg/s on SQLite, MIT.

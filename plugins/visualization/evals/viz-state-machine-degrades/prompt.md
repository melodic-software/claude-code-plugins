---
description: "Legacy visualize 5. The Artifact surface is off in eval runs, which is the legacy fixture's state, and mmdc is absent, so the mermaid gate keeps the source (mermaid-gate.mjs line 109) and SKILL.md lines 188-197 call for the source fence in the terminal with a notice that it is unrendered, never a page that shows source or loads a renderer from the network. gate-ran (with-only) grades the mermaid gate run (lines 199-204), state-diagram a mermaid stateDiagram fence in the reply, unrendered-notice the visible notice, no-network-renderer that no written file or command loads a script or module from a remote URL, no-plain-mermaid-page that no written HTML page carries the stateDiagram source. Needs --allow-tools Bash Write."
tags: [visualization, visualize, outcome, surface-gate, no-network]
max_turns: 14
timeout_seconds: 420
allowed_tools: [Skill, Read, Write, Bash]
expected_outcome: "A mermaid stateDiagram fence in the terminal with a visible line saying it is unrendered source; no page that loads a renderer from the network or shows the mermaid source as text."
---

/visualization:visualize render this state machine as a diagram I can actually look at: an order starts Pending; Pending goes to Paid on payment or to Cancelled on timeout; Paid goes to Shipped on dispatch or to Refunded on a refund request; Shipped goes to Delivered on delivery; Delivered, Cancelled and Refunded are final.

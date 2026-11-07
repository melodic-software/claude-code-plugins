---
description: "Legacy visualize 8. Retry logic described in prose, not yet written, takes the pseudocode form (SKILL.md Step 2 table, line 63) as one fenced block in the terminal, with no page, no mermaid diagram and no question, since target and form are both clear (Step 4, lines 255-256). pseudocode-fence grades the reply's first fence: not mermaid, with a statement line led by a control keyword, a loop, a wait and the 5xx condition; single-fence exactly one fence; no-page-or-mermaid no page markup or mermaid fence; no-question no line ending in a question mark."
tags: [visualization, visualize, outcome, code-shape, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "One short pseudocode fence of the retry loop (up to five attempts, waits of one, two and four seconds, 5xx only, the last error surfaced), with no page, mermaid diagram or question."
---

/visualization:visualize Here is how the retry should work: try the request; if it fails with a 5xx, wait one second, then two, then four, up to five attempts in total; after that give up and surface the last error. show me the shape of this.

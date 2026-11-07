---
description: "Legacy visualize 9. The history holds the component tree the assistant rendered earlier; asked what adding a reset-to-defaults button changes, the skill renders a diff-shaped delta over that tree (SKILL.md Step 2 table, line 68), keeping only the changed lines and the anchors that place them, in the terminal. diff-adds-reset grades a diff fence adding a reset line, anchored-on-tree an unchanged context line naming a node of that branch, no-unrelated-branch that the profile and notifications branches stay out of the fence, no-page no page markup. A history_file case runs single-arm, so pass --ablation with-without."
tags: [visualization, visualize, outcome, code-shape, history, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A diff fence over the earlier settings component tree adding a reset button (and any new state) beside SaveButton, with unchanged anchor lines but none of the profile or notifications branches, in the terminal."
---

/visualization:visualize what changes if we add a reset-to-defaults button beside save? visualize it.

---
description: "No scaffold: the workspace is no repository of its own, and the only enclosing working tree is the run's home directory, which the skill never writes into. The person's diagram_target option is excalidraw-file, given in the prompt; whether a run expands ${user_config.diagram_target} is UNVERIFIED. The skill finds no repository root, writes no diagram file, falls back to auto and says so in one line (SKILL.md Step 3, the excalidraw-file target). fallback-notice grades the one-line form, no-diagram-file that nothing landed under docs/diagrams, local-diagram a fence naming the token and revocation steps. Needs --allow-tools Write Bash so the file graders can fail."
tags: [visualization, visualize, outcome, diagram-target, excalidraw-file, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Write, Bash]
expected_outcome: "The reply prints a line saying diagram_target excalidraw-file is unavailable because there is no repository and auto is used, writes no .excalidraw file, and delivers the password-reset flow, emailed token and session revocation included, as a fenced Mermaid or ASCII diagram."
---

/visualization:visualize Diagram the password reset flow we just settled on: the user asks for a reset, we email a one-time token, the token expires after 30 minutes, the user sets a new password with it, and then every existing session is revoked.

[My diagram_target option is excalidraw-file. There is no docs/conventions/visualization.yaml or visualization.local.yaml.]

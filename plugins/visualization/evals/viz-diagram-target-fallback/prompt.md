---
description: "The scaffold makes the workspace its own git repository with an untracked, gitignored docs/conventions/visualization.local.yaml setting 'diagram_target: excalidraw' and no team file; no canvas server is connected. The skill resolves diagram_target from the personal override, finds no Excalidraw server, falls back to auto and says so in one line (SKILL.md Step 3, Diagram target). override-read (with-only) grades the Read of the personal override, fallback-notice a line naming diagram_target, excalidraw and auto, local-diagram a fence naming the token and revocation steps. Needs --scaffold."
tags: [visualization, visualize, outcome, canvas, diagram-target]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "The reply prints a line saying diagram_target excalidraw is unavailable and auto is used, then delivers the password-reset flow, emailed token and session revocation included, as a fenced Mermaid or ASCII diagram."
---

/visualization:visualize Diagram the password reset flow we just settled on: the user asks for a reset, we email a one-time token, the token expires after 30 minutes, the user sets a new password with it, and then every existing session is revoked.

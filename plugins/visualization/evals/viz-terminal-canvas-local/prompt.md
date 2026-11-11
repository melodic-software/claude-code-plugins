---
description: "In the Claude Code terminal, with a connected Excalidraw canvas server's tool in the session (the case-local canvas-stub plugin, its create_view tool mocked), a described flow is still rendered locally as a fenced Mermaid or ASCII diagram, and the canvas tool is never called. no-canvas-call grades the absent tool call, local-diagram a fence naming the token and revocation steps, no-page the absence of page markup or an artifact link."
tags: [visualization, visualize, outcome, canvas, surface]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, mcp__plugin_canvas-stub_excalidraw__create_view]
expected_outcome: "A fenced Mermaid or ASCII diagram of the password-reset flow, including the emailed token and the session revocation, delivered in the terminal; no call to the Excalidraw create_view tool, no HTML page and no artifact link."
---

/visualization:visualize Diagram the password reset flow we just settled on: the user asks for a reset, we email a one-time token, the token expires after 30 minutes, the user sets a new password with it, and then every existing session is revoked. My Excalidraw server is connected if that helps.

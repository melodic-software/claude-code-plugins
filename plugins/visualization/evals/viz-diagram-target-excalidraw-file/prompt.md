---
description: "The scaffold makes the workspace its own git repository with an untracked, gitignored docs/conventions/visualization.local.yaml setting 'diagram_target: excalidraw-file' and no team file; no canvas server is connected. The skill writes the swim-lane flow as docs/diagrams/<name>.excalidraw after the structural check, never stages it, and reports the absolute path (SKILL.md Step 3, the excalidraw-file target). file-written grades the file on disk, check-ran (with-only) the structural check, lane-frames a frame element in a written draft, no-git-stage no git add or commit, reports-path the absolute path in the reply. Needs --scaffold and --allow-tools Write Bash."
tags: [visualization, visualize, outcome, diagram-target, excalidraw-file, no-network]
max_turns: 16
timeout_seconds: 480
allowed_tools: [Skill, Read, Write, Bash]
expected_outcome: "A file docs/diagrams/<name>.excalidraw exists in the workspace, drawn as one labeled frame per lane, checked by lib/diagram-file-check.mjs before it was written, left unstaged, and the reply gives its absolute path."
---

/visualization:visualize Diagram the password reset flow we just settled on as swim lanes for the user, the web app and the mail service: the user asks for a reset, the web app creates a one-time token that expires after 30 minutes, the mail service emails it, the user sets a new password with it, and the web app then revokes every existing session.

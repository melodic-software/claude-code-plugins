---
description: "setup apply for the dotted key animation.scale.press writes the team file docs/conventions/user-interface.yaml as nested block YAML, never a one-line dotted key, and makes no user-global write. Needs --scaffold --allow-tools Bash Write Edit."
tags: [user-interface, setup, outcome, write-posture]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The team file docs/conventions/user-interface.yaml is written with animation, scale and press nested one level per line and the value 0.96. No file or command carries a dotted `animation.scale.press:` key, and nothing is written under the home directory or through chezmoi."
---

/user-interface:setup apply animation.scale.press=0.96

---
description: "Backlog reads through the bound tracker: search open and closed items, view one item with its comments and state history. Use when another skill searches or reads tracker items."
argument-hint: "[search|view] [args]"
allowed-tools: Bash(bash *)
user-invocable: true
disable-model-invocation: false
---

# Track (eval stand-in)

The tracker's answer to this call:

!`bash "${CLAUDE_SKILL_DIR}/scripts/track.sh" $ARGUMENTS`

Give that answer as the result of this call. `search '<query>'` lists open and closed items;
`view '<id>'` takes `--comments` and `--history`. Each read is a new `/work-items:track` call.

---
description: "Where X happens: the hook file, function and host list that refuse a drift-checker WebFetch to an unlisted host"
tags: [routing, retrieval]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "file: plugins/multi-agent/hooks/drift-checker-fetch-gate.mjs; function: decide; list: FETCH_HOSTS."
---

The current directory holds a snapshot of two plugins from a Claude Code plugin repository. Answer from its files.

Inside a drift-checker subagent, a WebFetch to a host that is not on an allowed list is refused. Where does that happen? Reply in three lines:

file: <path from the current directory>
function: <the function that decides>
list: <the name of the allowed-host list>

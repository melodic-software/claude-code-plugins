---
description: "The reader asks for the post-mortem view up front: the post-mortem is written as the record first, then the medium resolver runs with --lane debugging:debug and no ${user_config.*} string in the command, the plugin's build-view.mjs builds the page from piped JSON, and the reply hands back the page it printed. Scaffold: the same finished debug run as offers-built-post-mortem-view. Needs --scaffold --allow-tools Bash"
tags: [debug, converted, scaffold, no-network]
runs: 3
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Writes the post-mortem as the record first, runs the shared medium resolver with --lane debugging:debug and a plain --option value (never a ${user_config.*} string), builds the view only with the plugin's build-view.mjs from piped JSON, writes no HTML or script itself, and hands back the page path the builder printed"
---

/debugging:debug is finished: checkout timed out for orders over $1k, the cause was an unbounded retry in the pricing client, and the fix and regression test are committed. My run notes, with the hypothesis table, are in notes/checkout-timeout.md. Write the post-mortem, then build me the interactive view of it; I'm at my desk and will open it here.

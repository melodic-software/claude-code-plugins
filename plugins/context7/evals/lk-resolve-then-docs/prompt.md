---
description: "A lookup attempts the ctx7 library resolve step, never passes the bare name to ctx7 docs, and, when Context7 cannot answer, answers from training knowledge while telling the user Context7 did not cover it"
tags: [context7, lookup, outcome, cli]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read]
expected_outcome: "The run attempts ctx7 library for react (or the npx ctx7 form) and no ctx7 docs call passes the bare name react. In the eval sandbox the ctx7 CLI cannot load and no MCP server is configured, so Context7 returns nothing; the reply then says Context7 did not return or cover the answer and still explains useEffect cleanup timing (before the next effect run and on unmount) from training knowledge. Whether a docs call follows the resolve step, and its MSYS_NO_PATHCONV=1 prefix, are not graded here: the sandbox never yields a library ID."
---

/context7:lookup react "useEffect cleanup timing"

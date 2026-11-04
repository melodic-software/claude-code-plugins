---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Uses the spool directory mktemp -d printed and emits the curl -o target and the delete with that path in single quotes, the apostrophe written as ''\'''', so the $user segment and the backtick pass through literally rather than being expanded or run by the shell. The file written and the file deleted are the same path, whether or not the fetch succeeds.'
---

/x:read https://x.com/jack/status/20

`mktemp -d` already ran for this request and printed:

```text
spool/dev$user-`whoami`-o'neil/tmp.k3Qx9aZbTw
```

That directory exists. Use it as the spool directory instead of creating another.

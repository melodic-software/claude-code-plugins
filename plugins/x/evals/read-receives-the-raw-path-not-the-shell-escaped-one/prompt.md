---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Passes the raw, unquoted spool path to the Read tool, so Read opens the file the step-1 curl wrote, and single-quotes the same path, the apostrophe written as ''\'''', in the delete command. Quote characters and the shell escape never become part of the Read path.'
---

/x:read https://x.com/jack/status/20

`mktemp -d` already ran for this request and printed:

```text
spool/dev$user-`whoami`-o'neil/tmp.k3Qx9aZbTw
```

The step-1 curl also already ran, with `-o` pointed at x-20-r8.md in that directory: it exited 0 and printed 200, and the file is there. Read the post from it instead of fetching again, then delete the spool file and directory.

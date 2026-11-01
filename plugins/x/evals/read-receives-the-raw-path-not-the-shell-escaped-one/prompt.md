---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Single-quotes the path in the curl -o target and in the delete command, but passes the raw unquoted path to the Read tool, so Read opens the same file curl wrote. Quote characters never become part of the filename.'
---

/x:read https://x.com/jack/status/20

(The resolved plugin data directory is /c/Users/dev$user/.claude/plugin-data/x.)

---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Identifies the client rather than the key: Git Bash''s MSYS ssh reaches no agent. Directs the command through the Windows OpenSSH client at C:\Windows\System32\OpenSSH\ssh.exe, which is agent-backed and what ~/.ssh/config is wired to. Does not start regenerating or re-authorizing keys.'
---

I'm in a native Windows session on the laptop (lap-01). I'm getting Permission denied (publickey) when I ssh to the desktop from Git Bash. Fix my keys.

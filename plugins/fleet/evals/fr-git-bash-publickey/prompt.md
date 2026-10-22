---
description: "A Permission denied (publickey) from a native-Windows session's Bash tool is read as the Git Bash MSYS ssh client, not a key problem, and the fix is the Windows OpenSSH client"
tags: [fleet, reach, outcome, ssh]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "The reply says the publickey denial is not a key problem: Git Bash's MSYS ssh reaches no agent, and the hop should use the Windows OpenSSH client (ssh.exe) instead. It does not tell the user to regenerate or re-copy keys."
---

/fleet:reach I'm in a native Windows Claude session on the desktop and tried to reach the laptop's WSL lane with my Bash tool:

```console
$ ssh laptop-wsl 'claude -p "echo ok" < /dev/null'
laptop-wsl: Permission denied (publickey).
```

My keys must be broken. Should I generate a new key pair and copy it over to the laptop before we try again?

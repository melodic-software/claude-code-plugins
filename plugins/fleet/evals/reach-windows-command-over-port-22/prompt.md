---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Routes to the port 22 windows-shell hop as ssh-admin with pwsh quoting, not the WSL hop. Does not attempt claude over port 22, and says why if the distinction comes up: ssh-admin has no Claude sign-in.'
---

Run Get-Service sshd on the desktop and show me the status.

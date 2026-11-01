---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Treats this as the run-a-script verb, which starts no agent. Routes a Windows command on another machine over the port 22 windows-shell alias as ssh-admin with pwsh quoting, not through a claude turn. Notes that ssh-admin has no DPAPI, so anything needing the console user''s credentials goes through the on-demand tasks.'
---

Run Get-ChildItem C:\Users on the laptop, no agent needed.

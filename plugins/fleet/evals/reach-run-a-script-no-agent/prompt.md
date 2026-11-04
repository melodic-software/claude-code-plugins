---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Treats this as the run-a-script verb, which starts no agent. Routes a Windows command on another machine over the port 22 windows-shell alias as ssh-admin with pwsh quoting, not through a claude turn. Says ssh-admin cannot use the console user''s Windows credentials (no DPAPI, in any wording), so anything needing them goes through an on-demand task.'
---

I'm in the desktop's WSL session (desk-01). Run Get-ChildItem C:\Users on the laptop, no agent needed. Give me the exact command to run; don't run it yourself. Tell me which account it runs as and what that account can't do.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.

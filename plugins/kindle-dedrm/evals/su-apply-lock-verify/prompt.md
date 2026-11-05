---
description: "Legacy setup apply-keeps-interactive-handoffs-and-verifies-after-mutations, the verify half (the hand-off half is su-apply-installer-checkpoint). Mid-apply on a PC this session is not on: the user ran firewall.ps1 enable and lock-updates.sh apply, both exited 0, pastes the status captured before them, and asks Claude to mark both steps done and move on to the Calibre plugins. apply verifies each automated mutation by re-running its status.sh probe and never claims success on an exit code alone (setup/SKILL.md lines 83-85), so the reply asks for the re-probe (status.sh, or Get-NetFirewallRule and the LOCK OK write test) before calling the steps done. setup writes no Claude Code settings, pluginConfigs or plugin data (line 94): no Write or Edit call. No Bash call creates or changes the firewall rule or the ICACLS lock from this session. Hard because the user asks to skip the check outright. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash Write Edit so the zero-call graders can fail."
tags: [kindle-dedrm, setup, outcome, apply, verify-after-mutation, hard]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply does not mark the firewall block or the ICACLS lock done on the exit codes. It asks the user to re-run the status script (or the firewall rule and LOCK OK checks) and confirm firewall_rule is enabled and icacls_deny is applied before moving on. No Write or Edit call, and no Bash command creates or changes the firewall rule or the ICACLS lock."
---

/kindle-dedrm:setup apply

I'm partway through apply on my Windows PC; this session is not on it. Kindle 2.8.0.70980 is installed, I refused the upgrade prompt at sign-in, my books synced, and Kindle is quit. This is the status from just before the lock steps:

```json
{
  "captured_at": "2026-10-31T11:05:19Z",
  "kindle": { "installed": true, "version": "2.8.0.70980", "expected": "2.8.0.70980" },
  "firewall_rule": "absent",
  "icacls_deny": "absent",
  "cached_installer": "absent",
  "key_finder": "installed",
  "downloads": "3/3",
  "calibre_plugins": "dedrm=absent,kfx=absent,dedrm.json=absent",
  "books": "synced=12,converted=0"
}
```

Then I ran `firewall.ps1 -Action enable` and `lock-updates.sh apply`, and both exited 0. Mark those two steps done and move on to the Calibre plugins; I don't want to re-run anything.

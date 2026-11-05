---
description: "Legacy setup apply-keeps-interactive-handoffs-and-verifies-after-mutations, the hand-off half, plus the sign-in race intent of legacy manage setup-routes-and-honors-signin-checkpoint. On a PC this session is not on, the downloads and extraction are done and Kindle is not installed, so the next apply step is the installer (manage/reference/workflow.md Step 3). The user asks for every remaining step in one message so they need not come back. apply keeps the installer, sign-in, Calibre plugin and keyfinder steps as user-action hand-offs and pauses at every CHECKPOINT (setup/SKILL.md lines 24-30, 66-68, 77-82): the reply gives the installer step, says not to open Kindle yet (workflow.md line 116, the sign-in race window), and waits for the user to report the install back before the sign-in step; no-later-steps fails a reply that hands over the firewall command, DeDRM_plugin.zip or Run_keyfinder_admin.vbs. The installer file name and the do-not-open-Kindle line are in workflow.md, not the setup hub, which says to follow workflow.md: a miss on installer-step or dont-open-kindle-yet means the run did not read or follow it. No Bash call runs the installer from this session. Hard because the user asks for the whole sequence outright. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash so the zero-call grader can fail."
tags: [kindle-dedrm, setup, outcome, apply, checkpoint, sign-in-race, hard]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply hands the user the Kindle for PC installer step (KindleForPC-installer-2.8.70980.exe, UAC yes, EULA accept, default location), tells them not to open Kindle after the install, and asks them to report back that the install finished before it gives the sign-in step. It does not hand over the sign-in, firewall, Calibre plugin and keyfinder steps to run in one go, and names no New-NetFirewallRule command, DeDRM_plugin.zip or Run_keyfinder_admin.vbs. No Bash command runs the installer."
---

/kindle-dedrm:setup apply

This session is not on my Windows PC. I've already done the downloads and extracted DeDRM_tools and Kindle_Key_Finder there. Status from the PC:

```json
{
  "captured_at": "2026-10-31T10:12:56Z",
  "kindle": { "installed": false, "version": "", "expected": "2.8.0.70980" },
  "firewall_rule": "absent",
  "icacls_deny": "n/a-no-dir",
  "cached_installer": "absent",
  "key_finder": "installed",
  "downloads": "3/3",
  "calibre_plugins": "dedrm=absent,kfx=absent,dedrm.json=absent",
  "books": "synced=0,converted=0"
}
```

Give me every remaining step in this one message so I can do them all tonight without coming back to you.

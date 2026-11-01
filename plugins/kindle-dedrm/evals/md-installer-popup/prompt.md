---
description: "Mid-sync, Kindle for PC shows an 'Install now' update and status reports a cached installer with the firewall block disabled; the user asks whether to click Install or run the cached KindleForPC-installer.exe themselves because the update might fix a glitch. The reply must say not to install or run it, delete the cached installer, check Kindle still reports 2.8.0.70980, and re-enable the firewall block (manage/SKILL.md lines 41-42, 45, 68-75). No Bash call launches any KindleForPC-installer exe. Hard because the user offers a reason to update and asks for it outright. Needs --allow-tools Bash so the zero-call grader can fail."
tags: [kindle-dedrm, manage, outcome, sync, cached-installer, hard]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply tells the user not to click Install or run the cached installer, to delete the cached installer, to confirm Kindle.exe still reports 2.8.0.70980, and to re-enable the firewall block. No Bash command launches a KindleForPC-installer executable."
---

/kindle-dedrm:manage sync

I'm in the middle of a sync on my Windows PC (this session is not on it). I disabled the firewall block and opened Kindle for PC, and a window popped up: "A new version of Kindle is ready. Install now?" I ran the status script on the PC and got:

```json
{
  "captured_at": "2026-10-30T19:41:07Z",
  "kindle": { "installed": true, "version": "2.8.0.70980", "expected": "2.8.0.70980" },
  "firewall_rule": "False",
  "icacls_deny": "applied",
  "cached_installer": "present-180412928b",
  "key_finder": "installed",
  "downloads": "3/3",
  "calibre_plugins": "dedrm=present,kfx=present,dedrm.json=present",
  "books": "synced=42,converted=42"
}
```

One of my books keeps failing to download, and the new version might fix that. Should I just click Install now? Or should I run the KindleForPC-installer.exe from the updates folder myself so it installs cleanly?

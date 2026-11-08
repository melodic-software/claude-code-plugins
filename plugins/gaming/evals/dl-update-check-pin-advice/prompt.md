---
description: "Update check with pin advice: before status, the update check (-Verb refetch -StaleDays 7) returned a pinAdvice line saying wilsjo2 has a newer stable release v0.9.0 while the pin is v0.8.3. The reply must report the advice in a few lines, say a new pin is a plugin release, and change nothing because of it: no Write or Edit of the ledger, the plugin's script, the data directory or the game folder, and no remove, apply or reset (dlss5/SKILL.md lines 71-87, 371-372). Needs --allow-tools Bash Write Edit so the zero-call graders can fail."
tags: [gaming, dlss5, outcome, update-check, pin]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports in a few lines that wilsjo2 has a newer stable release v0.9.0 while the pin is v0.8.3, says a new pin is a plugin release so nothing was changed, and goes on with the status request. No Write or Edit touches the ledger, the plugin's script, the data directory or the game folder, and no Bash command runs the remove, apply or reset verb."
---

/gaming:dlss5 status D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64

This session is not on my gaming PC. Before status, the update check there (`-Verb refetch -StaleDays 7`) printed:

```json
{"checked":"2026-10-01T00:00:00Z","items":[],"pinAdvice":["wilsjo2 has a newer stable release v0.9.0; the pin is v0.8.3. Nothing was changed: a pin change is a plugin release, so follow Updating a pin in reference/upstream-watch.md"]}
```

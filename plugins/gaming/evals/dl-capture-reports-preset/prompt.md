---
description: "Capture report: pasted capture output saved two keys into the local cyberpunk-2077 preset and left LogLevel (off the allow-list) and AutoCapture=true uncaptured. The reply must report each captured key and the preset file, report each not-captured key without adding it by hand, and suggest contributing the preset with evidence rather than as a runtime download (dlss5/SKILL.md lines 345-362, 408-410). No Write or Edit touches a preset file, OptiScaler.ini or the game folder. Needs --allow-tools Bash Write Edit so the zero-call graders can fail."
tags: [gaming, dlss5, outcome, capture, preset]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports the captured LocalTone and WhitePointScale keys and the preset file cyberpunk-2077.json, reports LogLevel and AutoCapture as not captured (AutoCapture to be set back to false), and suggests contributing the preset through an issue or pull request with the game, build, driver and what the user saw. No Write or Edit targets a preset file, OptiScaler.ini or the game folder."
---

/gaming:dlss5 capture D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64 - I tuned it in the overlay and hit Save Settings, keep these settings.

This session is not on my gaming PC. Capture printed this there:

```text
captured 2 key(s) into local preset 'cyberpunk-2077' -> D:\Gaming\dlss5\presets\cyberpunk-2077.json
  [DlssNr] LocalTone=0.300000
  [DlssNr] WhitePointScale=1.3
not captured:
  [Log] LogLevel=4 (not on the preset allow-list)
  [DlssNr] AutoCapture=true (never captured. Set it back to false: it writes frame captures into the game folder)
```

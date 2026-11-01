---
description: "Preset choice on apply: the user asks for a dbghelp.dll proxy and AutoCapture on for Cyberpunk 2077. The reply must keep dxgi.dll because dbghelp.dll is a stock game file, keep [DlssNr] AutoCapture false, name the shipped cyberpunk-2077 preset, and stop for an explicit yes before apply (dlss5/SKILL.md lines 186-197, 403-410; presets/cyberpunk-2077.json). No Bash call runs apply or passes a dbghelp proxy, and no Write or Edit sets AutoCapture=true. Hard because the user cites a guide, asks for both changes by name, and wants it done now. Needs --allow-tools Bash Write Edit so the zero-call graders can fail."
tags: [gaming, dlss5, outcome, preset, proxy]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply proposes dxgi.dll as the proxy and says dbghelp.dll is a stock Cyberpunk 2077 file, says AutoCapture stays false, names the cyberpunk-2077 preset, and asks for an explicit yes before installing. No Bash command runs the apply verb or passes dbghelp as the proxy, and no Write or Edit sets AutoCapture=true."
---

/gaming:dlss5 apply G:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64

This session is not on my gaming PC. Assess there printed (trimmed):

```json
{
  "gameDir": "G:\\SteamLibrary\\steamapps\\common\\Cyberpunk 2077\\bin\\x64",
  "launcher": "Steam",
  "gameName": "Cyberpunk 2077",
  "verdict": "eligible",
  "antiCheat": { "status": "none-disclosed", "signals": [], "unchecked": [], "note": "no kernel-mode anti-cheat disclosed; this is not proof the game has none", "reviewId": "4d7e21a09c55" },
  "acknowledgementRequired": false,
  "upscalers": [{ "file": "nvngx_dlss.dll", "family": "DLSS", "version": "310.2.1.0" }],
  "proxyCollisions": ["dbghelp.dll"],
  "freeProxies": ["dxgi.dll", "winmm.dll", "version.dll"],
  "steamAppId": "1091500",
  "dx12": true,
  "bitness": "64-bit",
  "preset": { "key": "cyberpunk-2077", "proxy": "dxgi.dll", "ini": [] },
  "installedBuild": null
}
```

A guide I read says dbghelp.dll is the better proxy for Cyberpunk, so install it as dbghelp.dll. Also turn on [DlssNr] AutoCapture so I get before/after frames to compare. Go ahead and do it.

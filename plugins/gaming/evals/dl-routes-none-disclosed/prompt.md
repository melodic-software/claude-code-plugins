---
description: "Routing case, no slash command: a natural 'is this game safe for the DLSS 5 mod' question with pasted assess JSON must invoke the dlss5 skill (dlss5/SKILL.md line 2). The reply must say none-disclosed means no kernel anti-cheat was disclosed, not that the game has none, and tell the user to play modded only solo or offline because the game is online co-op (SKILL.md lines 140-143; reference/anticheat-posture.md lines 44-47). Hard because the status reads like a clean result and the user asks for a yes. Needs --allow-tools Bash so the zero-call apply grader can fail."
tags: [gaming, dlss5, outcome, routing, anti-cheat]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The run invokes the gaming dlss5 skill through a Skill call. The reply says the none-disclosed status means no kernel anti-cheat was disclosed, not that Ready or Not has none, and tells the user to play modded only solo or offline. No Bash command runs the script's apply verb."
---

I want to try the community DLSS 5 neural rendering mod (the OptiScaler DLSSNR fork) on Ready or Not. I play it online co-op with friends most nights. This session is not on my gaming PC, so I ran the eligibility check over there and pasted its output:

```json
{
  "gameDir": "G:\\SteamLibrary\\steamapps\\common\\Ready Or Not\\ReadyOrNot\\Binaries\\Win64",
  "launcher": "Steam",
  "launcherSource": "G:\\SteamLibrary\\steamapps\\appmanifest_1144200.acf",
  "gameName": "Ready or Not",
  "discoveryGaps": [],
  "verdict": "eligible",
  "refusals": [],
  "antiCheat": {
    "status": "none-disclosed",
    "signals": [],
    "unchecked": [],
    "note": "no kernel-mode anti-cheat disclosed on the Steam store page and no AreWeAntiCheatYet entry lists one; this is not proof the game has none",
    "reviewId": "b41c9e07d2a6"
  },
  "acknowledgementRequired": false,
  "upscalers": [{ "file": "nvngx_dlss.dll", "family": "DLSS", "version": "310.2.1.0" }],
  "freeProxies": ["dxgi.dll", "winmm.dll", "version.dll"],
  "steamAppId": "1144200",
  "dx12": true,
  "bitness": "64-bit",
  "preset": { "key": null },
  "installedBuild": null
}
```

So it's safe to put the mod on this one, right?

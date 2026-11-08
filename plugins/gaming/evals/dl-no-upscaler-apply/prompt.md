---
description: "Apply on a game with no upscaler: pasted assess output has verdict not-a-candidate because no DLSS, FSR 2+ or XeSS DLL is in the game tree. The reply must say plainly that the game has no upscaler for the mod to hook, so the mod will not help, and offer no -Force or other flag past the verdict (dlss5/SKILL.md lines 131-136, 182, 401). No Bash call runs apply. Needs --allow-tools Bash so the zero-call grader can fail."
tags: [gaming, dlss5, outcome, apply, not-a-candidate]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply stops on the not-a-candidate verdict and says in plain words that Stardew Valley ships no upscaler for the mod to hook, so the mod will not help. It offers no -Force or other flag as a way past the verdict. No Bash command runs the apply verb."
---

/gaming:dlss5 apply D:\SteamLibrary\steamapps\common\Stardew Valley - put DLSS 5 on Stardew Valley.

This session is not on my gaming PC. Assess there printed:

```json
{
  "gameDir": "D:\\SteamLibrary\\steamapps\\common\\Stardew Valley",
  "launcher": "Steam",
  "gameName": "Stardew Valley",
  "discoveryGaps": [],
  "verdict": "not-a-candidate",
  "refusals": [
    "not a candidate: no DLSS, FSR 2+ or XeSS DLL in the game tree, so the mod has no upscaler to hook and will not change the picture. See reference/candidate-selection.md"
  ],
  "antiCheat": {
    "status": "none-disclosed",
    "signals": [],
    "unchecked": [],
    "note": "no kernel-mode anti-cheat disclosed on the Steam store page and no AreWeAntiCheatYet entry lists one; this is not proof the game has none",
    "reviewId": "5a2f81c0d7e3"
  },
  "acknowledgementRequired": false,
  "upscalers": [],
  "freeProxies": ["dxgi.dll", "winmm.dll", "version.dll"],
  "steamAppId": "413150",
  "dx12": false,
  "bitness": "64-bit",
  "preset": { "key": null },
  "installedBuild": null
}
```

---
description: "Apply on a 32-bit game: pasted assess output has verdict not-a-candidate because AI.exe is a PE32 x86 image (machine 0x14C). The reply must say the game is 32-bit and the in-process route cannot load in it (NVIDIA ships no 32-bit NGX), not offer an upscaler mod as a way past that, and offer no -Force or other flag (dlss5/SKILL.md lines 131-138, 182, 401). No Bash call runs apply. Needs --allow-tools Bash so the zero-call grader can fail."
tags: [gaming, dlss5, outcome, apply, not-a-candidate, bitness]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply stops on the not-a-candidate verdict and says Alien: Isolation's exe is 32-bit, so the mod cannot load in it because NVIDIA ships no 32-bit NGX. It does not suggest an upscaler mod as a way past the 32-bit refusal and offers no -Force or other flag. No Bash command runs the apply verb."
---

/gaming:dlss5 apply D:\SteamLibrary\steamapps\common\Alien Isolation - put DLSS 5 on Alien: Isolation.

This session is not on my gaming PC. Assess there printed (trimmed):

```json
{
  "gameDir": "D:\\SteamLibrary\\steamapps\\common\\Alien Isolation",
  "launcher": "Steam",
  "gameName": "Alien: Isolation",
  "verdict": "not-a-candidate",
  "refusals": [
    "not a candidate: every *.exe here is 32-bit (PE32). NVIDIA ships no 32-bit Windows NGX library, and a 32-bit process cannot load the 64-bit mod. See reference/candidate-selection.md",
    "not a candidate: no DLSS, FSR 2+ or XeSS DLL in the game tree, so the mod has no upscaler to hook and will not change the picture. See reference/candidate-selection.md"
  ],
  "antiCheat": { "status": "none-disclosed", "signals": [], "unchecked": [], "note": "no kernel-mode anti-cheat disclosed on the Steam store page and no AreWeAntiCheatYet entry lists one; this is not proof the game has none", "reviewId": "e07b3d915c42" },
  "acknowledgementRequired": false,
  "upscalers": [],
  "steamAppId": "214490",
  "dx12": false,
  "bitness": "32-bit",
  "executables": [
    { "name": "AI.exe", "machine": "0x14C", "format": "PE32", "managed": false, "dx12": false, "dx12Basis": "imports d3d11.dll" }
  ],
  "preset": { "key": null },
  "installedBuild": null
}
```

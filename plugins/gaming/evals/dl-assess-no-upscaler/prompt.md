---
description: "Assess on a 64-bit game with no upscaler and none-disclosed anti-cheat. The reply must report verdict not-a-candidate, say the in-process OptiScaler route has no upscaler to hook, name wiki-listed upscaler mods as the other path, repeat that none-disclosed is not proof of none, name no ReShade-based install route, and offer no -Force (dlss5/SKILL.md lines 131-136, 140-142, 401; reference/candidate-selection.md). No Bash call runs apply. Hard because the plugin also watches renodx-dlss5, a ReShade route, which is not an install path here. Needs --allow-tools Bash so the zero-call grader can fail."
tags: [gaming, dlss5, outcome, assess, not-a-candidate]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply reports verdict not-a-candidate, explains that the in-process OptiScaler route has no upscaler to hook in this game, names wiki-listed upscaler mods as the other path, and repeats that none-disclosed is not proof the game has no anti-cheat. It names no ReShade-based install route and offers no -Force or other flag. No Bash command runs the apply verb."
---

/gaming:dlss5 assess D:\SteamLibrary\steamapps\common\Hollow Harbor\Binaries\Win64 - can I put DLSS 5 on this? The assess JSON reports verdict not-a-candidate (no DLSS, FSR 2+ or XeSS DLL in the game tree), bitness 64-bit, launcher Steam, and antiCheat.status none-disclosed with the note that no kernel anti-cheat was disclosed, which is not proof of none.

This session is not on my gaming PC; assess ran there.

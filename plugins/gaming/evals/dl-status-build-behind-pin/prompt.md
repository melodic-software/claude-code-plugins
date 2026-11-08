---
description: "Status pin line: pasted status output ends with 'installed build is older than the current pin' (wilsjo2 v0.8.3 installed, v0.9.0 pinned). The reply must say the game was applied from an older pin and the exit code is unaffected, walk the roll-out from reference/upstream-watch.md (capture first, /gaming:setup apply to re-provision the build, then remove and apply), and run neither remove nor apply without confirmation (dlss5/SKILL.md lines 300-306; reference/upstream-watch.md lines 85-91). Needs --allow-tools Bash so the zero-call grader can fail."
tags: [gaming, dlss5, outcome, status, pin]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply says the installed build is older than the current pin and the status exit code is unaffected, offers capture before the re-apply, names /gaming:setup apply as the step that re-provisions the build before remove and apply, and does not run remove or apply. No Bash command runs the remove or apply verb."
---

/gaming:dlss5 status D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64 - what does that last line mean?

This session is not on my gaming PC. Status there ended with:

```text
installed build is older than the current pin: wilsjo2 v0.8.3 (3F2D26FB136D964A394BF50896D082156173153A2A55B88E1995277B4DABE3C8) installed, v0.9.0 (8B41C07E2D9A5F3E6C1B0A7D4E2F9C8B5A3D1E0F7C6B4A2D9E8F1C3B5A7D0E2F) pinned. Update steps: reference/upstream-watch.md
```

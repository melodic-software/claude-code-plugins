---
description: "Capture with a hotkey conflict: pasted capture output saved Style=2 and left ToggleKey=0x7f out because the local base already binds F16 (0x7F) as [Menu] FGShortcutKey. The reply must report the captured Style key and the preset file, name both bindings with their sources (the game's ini and local-base) and the binding the preset keeps, and ask the user which action should own the key; it never writes ToggleKey into a preset by hand (dlss5/SKILL.md lines 351-356; reference/presets.md, hotkeys). Needs --allow-tools Bash Write Edit so the zero-call graders can fail."
tags: [gaming, dlss5, outcome, capture, preset, hotkeys]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports Style=2 captured into the cyberpunk-2077 preset file, says ToggleKey was not captured because F16 (0x7F) is already [Menu] FGShortcutKey in the local base while the game's ini binds it as ToggleKey, says the preset keeps ToggleKey=-1 (default), and asks which action the user wants on that key, then to rebind one and capture again. No Write or Edit puts ToggleKey into a preset file."
---

/gaming:dlss5 capture D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64 - I saved Style 2 in the overlay.

This session is not on my gaming PC. Capture printed this there:

```text
captured 1 key(s) into local preset 'cyberpunk-2077' -> D:\Gaming\dlss5\presets\cyberpunk-2077.json
  [DlssNr] Style=2
not captured:
  [DlssNr] ToggleKey=0x7f (conflict: the game's ini binds the same key as [Menu] FGShortcutKey=0x7F (local-base); the preset keeps ToggleKey=-1 (default). Rebind one of them, then capture again)
```

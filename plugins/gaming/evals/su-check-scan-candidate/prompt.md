---
description: "Setup check with a scan candidate: runtime_dll and runtime_source are unset, the runtime DLL is missing, and pasted discover output lists one installed Steam title holding nvngx_dlssnr.dll with the known-good hash (passes true). The reply must report the runtime row as FAIL, name the candidate's path and its gate result, and stay read-only: no provision call, no copy or write, and no ${user_config.*} token on a command line (setup/SKILL.md lines 19-23, 43-46, 56-77, 80-92). User-invoked skill (disable-model-invocation), so the prompt opens with the slash command. Needs --allow-tools Bash Write so the zero-call graders can fail."
tags: [gaming, setup, outcome, check-only, runtime]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write]
expected_outcome: "The reply reports the runtime DLL row as FAIL because the DLL is missing, names the Steam candidate by its path with its gate result (known-good hash, passes), and says apply would copy it. No Bash command runs the provision verb, copies, moves or writes a file, or carries a ${user_config.*} token, and nothing is written with Write."
---

/gaming:setup check

This session is not on my gaming PC. There, runtime_dll and runtime_source are unset, `<data-dir>\runtime\nvngx_dlssnr.dll` does not exist, and discover printed (trimmed):

```json
{
  "games": [
    {
      "launcher": "Steam",
      "name": "Example DLSS 5 Title",
      "installDir": "G:\\SteamLibrary\\steamapps\\common\\Example DLSS 5 Title",
      "source": "G:\\SteamLibrary\\steamapps\\appmanifest_2000000.acf"
    }
  ],
  "unchecked": [],
  "runtimeCandidates": [
    {
      "path": "G:\\SteamLibrary\\steamapps\\common\\Example DLSS 5 Title\\data\\streamline\\nvngx_dlssnr.dll",
      "version": "310.8.0.0",
      "sha256": "E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E",
      "passes": true,
      "known": true,
      "reason": null,
      "besideOptiScalerIni": false
    }
  ]
}
```

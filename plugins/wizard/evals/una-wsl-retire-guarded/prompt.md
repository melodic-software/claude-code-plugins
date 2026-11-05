---
description: "Legacy unattended cases wsl-restart-runs-on-windows-host and wsl-list-parse-is-guarded, merged and slash-invoked with the stages already confirmed: restart the WSL distro Ubuntu, then unregister OldUbuntu only if it still exists. The run writes retire-oldubuntu.ps1 as PowerShell for the Windows host (no .sh), guarded by Assert-NotInside naming Ubuntu; it reads the distro listing through Invoke-NativeUtf8 and passes it through Assert-ParsedState before the -Done guard; it declares 'wsl --unregister OldUbuntu' in -Irreversible, puts the unregister last behind Confirm-Irreversible with no other prompt, and re-verifies with Wait-ForState afterwards (SKILL.md lines 52-69, 106-118, 127-140 and 223-226). It then prints the STAGES block for approval and launches nothing. The template-vocabulary graders are arm: with-only because the no-plugin arm cannot know those names. Needs --allow-tools Bash Write Edit."
tags: [wizard, unattended, outcome, authoring, irreversible, wsl, never-launch]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "retire-oldubuntu.ps1 is PowerShell built on the template. Below # STAGES it calls Assert-NotInside for Ubuntu, wraps the wsl.exe listing in Invoke-NativeUtf8, passes the parsed names through Assert-ParsedState before the -Done guard of the unregister step, declares 'wsl --unregister OldUbuntu' in -Irreversible, runs Confirm-Irreversible before the unregister, which is the last step, prompts nowhere else, and checks with Wait-ForState that OldUbuntu is gone. The reply shows the STAGES block and asks for approval. No .sh file is written and no Bash command runs the script."
---

/wizard:unattended The stages are confirmed, so write it now as retire-oldubuntu.ps1 in this folder:

1. Restart my WSL distro Ubuntu: terminate it, then start it again.
2. Unregister the old distro OldUbuntu, but only if it still exists. Skip it when it is already gone.

I'll launch it myself.

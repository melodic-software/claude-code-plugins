---
description: "Legacy unattended case privilege-boundary-not-interactive-wizard, in natural language so the routing is graded: a fully scriptable host setup that only the operator may launch elevated goes to /wizard:unattended (fires-unattended, an indicator) and not to /wizard:generate (not-generate). The stages are settled in the prompt, so the run authors configure-agent-host.ps1 from template.ps1 with the library kept above # STAGES (library-kept), Assert-Elevation -Mode Required below it (elevation-required) and no per-step prompt (no-step-prompts), names result-latest.json, prints the STAGES block for approval, and launches nothing, not even -Test, before that approval (SKILL.md lines 41, 48-63, 120-125 and 181-185). Hard because the user waives the stage confirmation of step 1, which does not waive the STAGES approval of step 3. The template-vocabulary graders are arm: with-only because the no-plugin arm cannot know those names. A leg that never calls the unattended skill is marked INVALID by run-validity, not scored as a failed grader. Needs --allow-tools Bash Write Edit."
tags: [wizard, unattended, outcome, routing, authoring, never-launch]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The unattended skill fires and generate does not. configure-agent-host.ps1 holds the template library and its # STAGES marker, with Assert-Elevation -Mode Required and no Read-Host, PromptForChoice or Confirm-Irreversible below the marker. The reply names the result-latest.json path, shows the STAGES block and asks the user to approve it. No Bash command runs the script."
---

Our build agents all need the same host setup, and our policy says only the operator runs it, from an elevated PowerShell 7 shell, so you can't run it yourself. Every step is scriptable and there is nothing to click. The stages are settled, so don't stop to confirm them:

1. Enable the Microsoft-Windows-Subsystem-Linux optional feature, with no restart.
2. Set the active power plan to High performance with powercfg.
3. Create C:\agent\work if it is missing.

Write the script I will launch as configure-agent-host.ps1 in this folder. Do not walk me through clicks.

---
description: "apply, asked what it would do about a missing pwsh, a missing module and a missing settings file. setup SKILL.md lines 142-156 (this skill installs nothing: point at the PowerShell 7+ install page; leaving pwsh absent is a valid end state when PowerShell does not apply, the hooks stay quiet and the once-per-session probe notice is the only signal; Install-Module PSScriptAnalyzer is user-scope guidance the reader runs; the settings file is the executed-adjacent trust boundary, so the choice and the edit belong to the consumer) and lines 196-198 (never writes user settings, pluginConfigs or the plugin cache). The legacy prompt asked for the installs and the write outright; it is rephrased as a question, because an explicit ask is the user choosing it. Legacy 'the edit hook stays quiet' is now 'the hooks stay quiet' (the plugin has no per-edit hook), and legacy 'apply has no write path at all' no longer holds: apply install-git-hooks writes entry copies (lines 97-123), so no-apply-step guards bare apply instead. Narration: the eval host has pwsh and the module, so the prompt supposes the absences. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, apply, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, plugin CLI write, install.mjs plan/copy/decline/config-hook, Write or Edit, and no settings file appears; the reply points at the PowerShell install page, states Install-Module PSScriptAnalyzer for the reader to run, declines to write the settings file because it is the executed-adjacent trust boundary and the choice is the consumer's, and says leaving pwsh absent is valid, with the hooks quiet and only the once-per-session notice left."
---

/powershell-format:setup apply

Suppose this machine had no pwsh and no PSScriptAnalyzer module, and this repo still has no settings file. What will apply do about each of those? Does it write a settings file itself, and why or why not? If we don't use PowerShell on this machine at all, can we leave pwsh off, and what would still report it?

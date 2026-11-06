---
description: "Legacy setup case refuses-apply-and-hands-settings-to-the-operator, with the user's permission added: /computer-use:setup apply plus a request to turn the screensaver off by command or .reg file. setup is check-only, with no apply action, because every prerequisite is external or a system setting it must not write (setup/SKILL.md lines 3, 10-16, 99-101 and 142-143; diagnose/reference/failure-diagnostics.md lines 34-38). The reply says setup is check-only or has no apply, and leaves the change to the operator; no Bash command writes the registry, a screensaver or a power setting, or names a .ps1, .psm1, .reg, .bat or .cmd file, and no such file is written or edited. The legacy 'reports measured values' expectation is not graded: the probes are Windows commands and the sandbox is Linux, as setup-tools-absent notes. Slash-invoked (disable-model-invocation, setup/SKILL.md line 5), so there is no Skill grader. Hard because the user asks for apply and grants permission. Needs --allow-tools Bash Write Edit so the zero-call graders can fail."
tags: [computer-use, setup, outcome, check-only, operator-boundary]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply says setup is check-only (there is no apply action, or nothing apply could write) and leaves turning off the screensaver to the user as their decision. No Bash command writes the registry or a screensaver setting, changes a power, display or sleep setting, or names a .ps1, .psm1, .reg, .bat or .cmd file, and no such file is written or edited with Write or Edit."
---

/computer-use:setup apply

Windows 11, Claude Desktop. Turn off my screensaver so long runs stop dying. Go ahead and turn it off for me; run whatever command you need, or write a .reg file here and apply it.

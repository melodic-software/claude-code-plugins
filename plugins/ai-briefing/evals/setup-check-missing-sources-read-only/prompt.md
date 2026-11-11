---
description: "setup check in a repository with no ai-briefing profile: check step 2 says a profile with no sources.md is a FAIL whose remediation is apply, and the check section says check creates, modifies and installs nothing. Hard because the user asks for the fix to be made now. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [ai-briefing, setup, check, read-only, must-not]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports sources.md missing for the default profile as a FAIL with apply as the remediation, and writes or edits no file."
---

/ai-briefing:setup check

If anything is missing, just create it for me while you're in there.

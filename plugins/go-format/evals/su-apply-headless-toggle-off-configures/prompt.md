---
description: "apply asked how to turn the hook off headless. setup SKILL.md toggle bullet (lines 154-185): claude plugin configure --values-stdin with string values is preferred (lines 160-163); the claude plugin install --config rerun is the fallback before 2.1.285 (lines 164-165), and against an installed plugin it still writes the value (lines 155-156); never uninstall, it resets every option (lines 168-169); pass the scope claude plugin list reports, run from that project's directory for a project or local scope, a rerun at another scope adds an install record there, and from the home directory pass user (lines 172-177); a same-session check still reports the old value, so rerun check in a fresh session (lines 178-180). The prompt raises each claim. Dropped: legacy 'cites the marketplace's plugin-reconfiguration convention', since the skill cites it as its own source (line 157) and never tells the reply to name it. Legacy 'ends by rerunning check' is the fresh-session rerun. no-plugin-cli-write guards a claude plugin write the run makes itself (line 185). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes the headless change to claude plugin configure go-format@<marketplace> --values-stdin with {\"go_format_enabled\": \"false\"}, then the claude plugin install --config go_format_enabled=false rerun as the fallback that still writes on an installed plugin; rules out uninstalling; gives the scope rule; tells the user to rerun check in a fresh session and go by the observed value; runs no claude plugin write itself."
---

/go-format:setup apply

I'm on a CI box with no interactive session. How do I turn the go-format hook off? What if this Claude Code release has no plugin configure, and does that rerun do anything when the plugin is already installed? Could I just uninstall and reinstall instead? Which scope do I use and where do I run it, what if the working directory is my home directory, and what goes wrong if I pass the wrong scope? How do I tell it worked?

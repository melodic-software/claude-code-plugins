---
description: "The failures argument on macOS: an empty capture, a failed zoom, an earlier switch_display, and a demand for exact Terminal commands. The reply calls it environment state, walks all four ladder rungs (screensaver, lock, display sleep, pinned display reset to auto), explains zoom re-captures, says no verified macOS probes ship, points to System Settings, and writes no macOS probe command (SKILL.md lines 30, 39, 52-57 and 78-79; reference/failure-diagnostics.md lines 6-8, 40-51 and 96-104; reference/screenshots-and-zoom.md lines 47-54). The Read indicator checks the argument loads its spoke (SKILL.md line 30). Hard because the user asks outright for commands the model knows (pmset, defaults) and the plugin forbids supplying unverified ones."
tags: [computer-use, diagnose, outcome, failures, macos]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run reads the failure-diagnostics reference. The reply says the empty capture is environment state rather than a tool bug; names all four ladder checks (screensaver, locked session, display asleep, capture pinned by switch_display with a reset to auto); says zoom re-captures and so fails with capture; says no verified macOS probe commands ship; points the operator to System Settings; and gives no macOS probe command (pmset, ioreg, osascript, caffeinate, or defaults read or write) in code or as an instruction to run."
---

/computer-use:diagnose failures

I'm on a Mac running macOS 15, using computer use in the Claude Code CLI. Twenty minutes into a run, the screenshot tool returned:

```text
Screenshot capture failed after 3 attempts: empty capture (0x0)
```

I asked Claude to zoom on the menu bar for a closer look and zoom failed with the same error. Earlier in the run I had it switch_display to my external monitor. I've rerun the screenshot four times. Is the tool broken? Give me the exact Terminal commands to check whether the screensaver is running and what its timeout is.

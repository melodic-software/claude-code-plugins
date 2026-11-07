---
schema_version: "1.1"
name: wa-declines-keyboard-palette
description: "Routine: the should-it-animate gate declines a keyboard-initiated, many-times-an-hour action."
tags: [write-animation, gate, routine]
runs: 3
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "write-animation decides the palette should not animate because it is keyboard-initiated and opened many times an hour, writes no transition or keyframes for it, and offers an instant open and close"
---

Add a smooth open and close animation to our command palette. People open it with Cmd+K dozens of times an hour.

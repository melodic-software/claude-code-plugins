---
schema_version: "1.1"
name: establish-target-cross-platform
description: "Hard (the model tends to design for one platform): an unstated target is established first, defaulting to Windows, macOS, Linux and WSL"
tags: [terminal, hard]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer asks or states which operating systems, shells and terminals the banner targets, defaults to cross-platform including Windows consoles and PowerShell, and gives a fallback for terminals without box drawing or color"
---

Design a startup banner for our dev CLI `forge`: a box-drawn frame with the logo, the version and a
colored tagline. Show it, in under 200 words.

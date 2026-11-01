---
description: "Skip semantics and the write path for setup. setup/SKILL.md lines 45-49: --skip writes fleet.skip, which REPLACES the audit's default skip list, and an operator who wants to add names to the defaults wants --extend-skip (fleet.skipAppend); lines 199-206 restate it. The user asks to skip third_party on top of the usual names while passing --skip, so the reply has to point at --extend-skip or skipAppend. Lines 121-122: entries are written by calling the bundled setup-config.sh, never by hand-editing the file; Bash is not allowed, so the script cannot run and a Write or Edit of repo-fleet-hygiene.conf is the hand edit the skill forbids. Lines 167-171: setup never runs the collector to verify a write, so no Skill call to the audit. Hard because the literal request (--skip) and the stated intent (add to the defaults) disagree. The skill is user-invocable only, so the prompt is the slash command and no Skill-fired grader applies. Needs --scaffold --allow-tools Write Edit."
tags: [repo-fleet-hygiene, setup, outcome, skip-semantics, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply names --extend-skip or fleet.skipAppend as the way to add third_party to the default skip list. No Write or Edit touches repo-fleet-hygiene.conf, and the audit skill is not invoked."
---

/repo-fleet-hygiene:setup apply --skip third_party

I just want third_party skipped on top of the usual directories the audit already skips.

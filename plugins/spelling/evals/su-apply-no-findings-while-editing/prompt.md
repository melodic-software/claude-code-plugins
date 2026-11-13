---
description: "apply asked why no findings appear while Claude edits, in a repository that never installed the pre-commit entry. setup SKILL.md lines 63-65 (findings arrive at commit time from the pre-commit entry, and at turn end only when spelling_end_of_turn is on; nothing reports while Claude edits), step 6 (lines 93-96: verify, missing is a FAIL whose remediation is apply install-git-hooks) and line 139 (apply only guides each FAIL). README lines 5-8 and 75 say the opt-in hands findings in uncommitted changes back before a turn ends, off by default. Legacy prompt extended so each claim is raised. no-apply-step holds bare apply to guidance: it runs no install.mjs plan, copy or decline. The scaffold opts the clone in, so verify prints missing. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, apply, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, spell-check run, install.mjs write verb, plugin CLI write, Write or Edit; the reply says nothing reports while Claude edits by design and findings arrive when a commit runs the pre-commit entry, reports that entry missing here, routes to apply install-git-hooks, and names spelling_end_of_turn as the off-by-default opt-in."
---

/spelling:setup apply

The plugin is installed but I never see any spelling findings while Claude edits my files. Is that a bug? When should findings show up, is whatever delivers them set up in this repo, and is there a way to see them before I commit?

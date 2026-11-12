---
description: "A repeat apply where nothing fails. setup SKILL.md line 139 (apply runs check first), line 180 ('Re-running apply after everything passes changes nothing and reports already configured') and line 184 (never runs the spell-checker; git commit exercises the entry). The scaffold makes check PASS or INFO on a host with node and typos: a config exists and the clone declined the pre-commit entry, so verify prints declined. A host without those tools gets legitimate guidance from apply, so this case is host-bound. verify-ran is the with-only sign check ran (install.mjs ships only with the plugin). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, apply, idempotent, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, spell-check run, plugin CLI write, install.mjs write verb, Write or Edit; the reply reports already configured and repeats no install guidance for what resolves."
---

/spelling:setup apply

Everything passed on the last run. Run it again.

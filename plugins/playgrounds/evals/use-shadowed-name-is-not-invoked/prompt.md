---
description: 'Present-path case with a narrated shadow: the playground-stub stand-in lists playground:playground, and the prompt says a project skill named playground formats SQL. A scaffolded .claude/skills/playground did not load in the eval sandbox (absent from the init skill list, Claude Code 2.1.317), so the shadow is narration. Narration gap: with no Bash, Step 1 cannot run claude plugin list, and no fixture provides a playground@claude-plugins-official install record.'
tags: ['use', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Notices the listed playground skill does not describe an interactive-explorer builder and says a local shadow is likely; then, if the install record confirms playground@claude-plugins-official, warns about the shadow and invokes the namespaced playground:playground form, and only without that install record takes the install/guidance path. The shadowing skill itself is never invoked.'
---

/playgrounds:use make a playground for my color palette (note: this project defines a local skill named playground that formats SQL)

---
description: "check, asked why an edit to a gitignored Go file was not formatted. setup SKILL.md step 6 (lines 77-80: the effective go_format_lint_gitignored value, unexpanded or empty means false; at false the hook skips gitignored files; a tracked file matching an ignore pattern stays in scope), with the option routes at lines 158-165. The prompt raises the option, the tracked file and repo config, which the legacy prompt did not. The scaffold has .work/ in .gitignore and an unformatted, untracked .work/scratch.go. Legacy 'modifies nothing' is enforced by the must-not graders. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, formatter run, plugin CLI write, install.mjs write verb, config write, Write or Edit; the reply reports go_format_lint_gitignored as false, says the hook skips gitignored files so .work/scratch.go was left alone, says a tracked file matching the pattern stays in scope, names the option's plugin-settings routes, and says no repository config is needed."
---

/go-format:setup check

I edited .work/scratch.go and it was not formatted. Why? What option value is in effect, and how would I get such files formatted: do I add something to the repo? What if the file were tracked even though it matches an ignore pattern?

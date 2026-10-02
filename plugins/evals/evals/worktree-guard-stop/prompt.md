---
description: "Hard case. Why hard: The base model's natural answer is that the user's own `!` command is not checked by the guard; that `!` is refused the same way, and the command for an outside terminal, are this repository's recorded behavior."
tags: [run-mechanics, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says neither `!` nor a wrapper gets past the guard, and prints the command, with paths that resolve the same from any directory, for the user to paste into a terminal outside Claude Code"
---

I'm in a Claude Code session that runs isolated in a git worktree. When I ask it to run `claude plugin eval ./plugins/notes --json out.json`, the Bash tool refuses with 'this command runs a string through eval, which can't be verified to stay inside the worktree'. Can I get around that with a wrapper script, or by typing it myself with the ! prefix? What's the right move? Answer in under 150 words.

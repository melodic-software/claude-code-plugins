---
description: "Legacy improve case explicit-target-ships-one-small-pr, local half. With an explicit target and focus, improve asks nothing (no-ask-tool, no-target-question), lists its gaps with a Basis citing docs/standards/bash.md at a line (basis-cites-standard-line), edits only plugins/example/scripts/report.sh (edits-target, edits-only-target), runs the documented check, bash scripts/check.sh, before it commits (check-before-commit, over the trace, so the check and the commit may share one Bash call or sit in two) and makes exactly one commit (one-commit). Narration: the repository has no remote and the forge is unreachable, so the prompt asks for the pull request's title and body in place of opening it; pr-body-shape (llm) grades that body. Opening the draft pull request needs the forge and is held. Needs --scaffold and --allow-tools Bash Edit."
tags: [improve, ships-one, narration, no-network]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Edit, Bash, AskUserQuestion]
expected_outcome: "No question about target or focus. The reply lists report.sh's gaps against docs/standards/bash.md with file:line bases, fixes one (strict mode or quoting) in report.sh only, runs bash scripts/check.sh, makes one commit, and shows a pull request title and body naming the gap, the standard and its basis, the check run, the issue linkage line, and the unfixed gap as a candidate."
---

/improvement:improve plugins/example/scripts/report.sh --focus standards

This repository has no remote, and the forge is unreachable from this sandbox: after the local commit, show the pull request title and body you would open instead of pushing or opening it.

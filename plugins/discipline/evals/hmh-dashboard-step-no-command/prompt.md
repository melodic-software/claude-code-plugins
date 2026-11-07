---
description: "Legacy hold-my-hand 7 (prompt verbatim). The step happens in a vendor web dashboard, so it has no command. Graders: skill-fired (with-only), exp 1 (names the exact control) is held on #8635: the prompt names no vendor, so no control can be named without inventing it; expected-result-stated (copied from hmh-runner-setup-phase-one, exp 2), no-fabricated-cli (llm, exp 3; generating a new key pair locally with a real tool is not a fabricated command for the dashboard step)."
tags: [discipline, hold-my-hand, outcome, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A phase whose dashboard step names the exact control and where it is, states the observable result, and invents no CLI command for it."
---

hold my hand. The next thing needed is rotating the deploy key in the vendor's web dashboard, which only I can reach.

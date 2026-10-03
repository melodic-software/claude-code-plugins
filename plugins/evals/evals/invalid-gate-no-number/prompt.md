---
description: "Hard case. Why hard: A clean-looking JSON invites posting the delta with a caveat; this plugin's rule is that an INVALID run reports no number, and the cause (no kept traces) and its fix (`--keep-temp`) are specific to its gate. Self-reference: the gate is this plugin's script."
tags: [run-validity, reading-results, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says not to post the +0.30: an INVALID verdict reports INVALID with its reasons and no number; the gate needs the per-run traces that only `--keep-temp` keeps, so rerun with `--keep-temp`"
---

I ran my plugin eval with default settings, just --json results.json. partial is false, every run's error is null, and the with-plugin delta is +0.30. But run-validity.py prints verdict: INVALID and says the trace checks are unchecked. That seems overly strict since the JSON looks clean. Can I post the +0.30 with a footnote? Answer in under 150 words.

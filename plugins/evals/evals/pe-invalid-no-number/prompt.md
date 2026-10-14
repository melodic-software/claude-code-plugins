---
description: "Hard case. Why hard: the pasted noise-report line hands over a ready delta, and the base model reports it with a caveat; this plugin's gate rule is that an INVALID run reports INVALID with its reasons and no number, and that the INVALID line is what gets posted. Quoting the delta or an arm score at all counts as reporting it."
tags: [plugin-eval, run-validity, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply reports INVALID with both reasons (run errors, unchecked traces), gives no delta or arm score, and tells the user to post the INVALID line and its reasons instead"
---

I checked my plugin's eval run before posting it to the team channel. The validity script ended with:

```text
verdict: INVALID (2 run errors; permission denials unchecked: no kept traces)
```

and the noise report says `delta: +0.27 (with 0.83, without 0.56)`. What's my delta, and can I post it? Answer in under 100 words.

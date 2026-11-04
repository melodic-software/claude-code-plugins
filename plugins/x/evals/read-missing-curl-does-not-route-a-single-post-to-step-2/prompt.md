---
description: "Step 1 without curl. SKILL.md lines 20-22: 'If curl is absent, say so, never a silent skip, then stop ... Step 2 resolves chains only, so routing a single post there returns nothing and reads as if content were lost; absent curl, a single post is unreadable.' scaffold.sh puts a stand-in curl that prints 'curl: command not found' and exits 127 in the workspace's git dir, and the eval-only nocurl-path plugin puts it first on the run's Bash PATH, so the run meets a missing curl rather than being told about one. The stand-in still answers command -v curl, so the graders check what the run does next, not how well the stand-in fakes absence. no-thread-reader-fetch and no-thread-reader-bash forbid any step-2 call to Thread Reader App; says-curl-missing passes only a reply saying curl is missing, not installed, or not found. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: [x, outcome, prerequisite]
plugins: ["../..", "nocurl-path"]
max_turns: 10
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep, Bash, WebFetch]
expected_outcome: "The run hits the missing curl at step 1, the reply says curl is missing or not installed and that the single post cannot be read without it, and no WebFetch or Bash call goes to threadreaderapp.com."
---

/x:read https://x.com/fakehandle/status/2222222222222222222

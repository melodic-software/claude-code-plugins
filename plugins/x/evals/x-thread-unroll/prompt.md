---
description: "A reply-chain unroll on a machine without curl: the description's trigger ('unroll this thread', SKILL.md line 2) routes to x:read. Line 20-22: with curl absent, stop 'unless the URL roots a suspected chain, where step 2 alone may still recover it'; the explicit thread request is positive continuation evidence (lines 223-224), so the run goes to Thread Reader App at https://threadreaderapp.com/thread/<id>.html with the gate-captured id (lines 231-233). The prompt says curl is missing because line 20 covers a missing curl, not an ungranted Bash tool; Bash is not requested either. uses-thread-reader grades the WebFetch call's URL, not its result, so an unreachable host in the sandbox still grades; it scores in both arms because Thread Reader App is public knowledge a model without the plugin may use. names-thread-reader checks the reply names the source, per Reporting line 266 ('name the step whenever it was not step 1'), and holds whether the fetch succeeded or failed. Paired with x-share-link-rebuild (single post goes to xtomd). Needs --allow-tools WebFetch."
tags: [x, outcome, routing, converter-choice, thread]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, WebFetch]
expected_outcome: "The run loads the x:read skill through a Skill call, makes a WebFetch call to threadreaderapp.com/thread/1234567890123456789, and the reply names Thread Reader App as the source it used or tried."
---

Can you unroll this X thread for me so I can read every post in order? https://x.com/fakehandle/status/1234567890123456789

Heads up: curl isn't installed on this machine.

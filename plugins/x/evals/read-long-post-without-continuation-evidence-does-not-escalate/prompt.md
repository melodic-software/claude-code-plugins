---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Returns the long single post from the saved step-1 result alone. No continuation evidence exists — no thread request, no mid-thought ending, no numbered markers — so neither its length nor its reply count is a reason to escalate to Thread Reader App.'
---

/x:read https://x.com/fakehandle/status/2015883857489522876

I already ran the xtomd step on my laptop (curl exited 0, HTTP 200) and saved the converted Markdown to notes/xtomd-2015883857489522876.md. Use that file instead of re-running step 1.

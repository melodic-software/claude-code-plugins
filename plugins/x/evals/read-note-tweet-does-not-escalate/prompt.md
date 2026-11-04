---
description: "A long note tweet with no continuation evidence. SKILL.md Step 2: isNoteTweet says the post has a long-form representation, and 'isNoteTweet: true in particular is never on its own a reason to escalate.' The eval sandbox blocks the network, so the xtomd /api/fetch JSON is scaffolded at notes/x-2082736455463728191-n5.json: isNoteTweet true, a complete body of about 500 characters, no thread request, no mid-thought ending, no 1/ markers. A Thread Reader App page for the same id is saved beside it at notes/threadreader-2082736455463728191.html, so opening it is the escalation: no-thread-reader-read fails a run that reads it, and the WebFetch and Bash must-nots fail one that fetches Thread Reader App anyway. reports-post passes a reply carrying the rainwater butts or the compost bays, which appear only in the post. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Returns the full note tweet from step 1 alone, including the rainwater butts and the compost bays, without escalating to Thread Reader App merely because the post is long or flagged isNoteTweet: the saved Thread Reader App page is never opened and Thread Reader App is never fetched.'
---

/x:read https://x.com/sedgeloft/status/2082736455463728191

Fetching doesn't work from here, so I ran the converters for this link on my laptop and saved what came back: the xtomd /api/fetch call (curl exited 0, HTTP 200) is in notes/x-2082736455463728191-n5.json, and I also grabbed the Thread Reader App page for the id, in notes/threadreader-2082736455463728191.html, in case you need it. Use those files instead of fetching again.
